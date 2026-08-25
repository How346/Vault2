import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/doc_category.dart';
import '../models/doc_item.dart';
import '../models/profile.dart';
import '../models/task_item.dart';
import '../utils/constants.dart';

/// Single source of truth for all on-device persistence.
/// Nothing here touches the network.
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  late final Box<DocItem> documents;
  late final Box<DocCategory> categories;
  late final Box<Profile> profiles;
  late final Box<TaskItem> tasks;
  late final Box settings;
  late final Directory _vaultDir;

  Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(DocCategoryAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(DocItemAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(ProfileAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(TaskItemAdapter());

    documents = await _openBox<DocItem>(HiveBoxes.documents);
    categories = await _openBox<DocCategory>(HiveBoxes.categories);
    profiles = await _openBox<Profile>(HiveBoxes.profiles);
    tasks = await _openBox<TaskItem>(HiveBoxes.tasks);
    settings = await _openPlainBox(HiveBoxes.settings);

    final docsDir = await getApplicationDocumentsDirectory();
    _vaultDir = Directory(p.join(docsDir.path, 'vault'));
    if (!_vaultDir.existsSync()) _vaultDir.createSync(recursive: true);

    await _seedCategories();
    await _seedProfiles();
  }

  /// A corrupted box must never brick the app: recreate it instead of throwing.
  Future<Box<T>> _openBox<T>(String name) async {
    try {
      return await Hive.openBox<T>(name);
    } catch (_) {
      await Hive.deleteBoxFromDisk(name);
      return Hive.openBox<T>(name);
    }
  }

  Future<Box> _openPlainBox(String name) async {
    try {
      return await Hive.openBox(name);
    } catch (_) {
      await Hive.deleteBoxFromDisk(name);
      return Hive.openBox(name);
    }
  }

  Future<void> _seedCategories() async {
    if (categories.isNotEmpty) return;
    for (final c in DefaultCategories.seed) {
      await categories.put(
        c['id'] as String,
        DocCategory(
          id: c['id'] as String,
          name: c['name'] as String,
          iconCodePoint: c['icon'] as int,
          colorValue: c['color'] as int,
          maskSensitive: c['mask'] as bool,
          isBuiltIn: true,
        ),
      );
    }
  }

  Future<void> _seedProfiles() async {
    if (profiles.isNotEmpty) return;
    await profiles.put(
      'me',
      Profile(
        id: 'me',
        name: 'Me',
        relation: 'Primary',
        colorValue: 0xFF0F766E,
        iconCodePoint: 0xe7fd,
        isDefault: true,
      ),
    );
  }

  /// Copies a picked/captured file into app-private storage and returns
  /// the new absolute path. The source is left untouched.
  Future<String> importFile(String sourcePath, {required String docId}) async {
    final dir = Directory(p.join(_vaultDir.path, docId));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final ext = p.extension(sourcePath);
    final target = p.join(
      dir.path,
      '${DateTime.now().microsecondsSinceEpoch}$ext',
    );
    await File(sourcePath).copy(target);
    return target;
  }

  Future<void> deleteDocFiles(DocItem doc) async {
    final dir = Directory(p.join(_vaultDir.path, doc.id));
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  /// Removes any files imported under [id] (used for both documents and
  /// task attachments, which share the same import path/id-keyed folder).
  Future<void> deleteFilesFor(String id) async {
    final dir = Directory(p.join(_vaultDir.path, id));
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  /// Vault root for imported document files.
  Directory get vaultDir => _vaultDir;

  /// Temp dir used for share exports; cleared on demand.
  Future<Directory> exportDir() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory(p.join(tmp.path, 'share'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<void> clearExports() async {
    final dir = await exportDir();
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  Future<void> wipeEverything() async {
    for (final doc in documents.values.toList()) {
      await deleteDocFiles(doc);
    }
    await documents.clear();
    await categories.clear();
    await profiles.clear();
    await tasks.clear();
    await _seedCategories();
    await _seedProfiles();
  }

  /// Overwrites every local record with a migrated payload (offline transfer).
  Future<void> replaceAll({
    required Map<String, dynamic> manifest,
    required List<({String docId, String name, List<int> data})> files,
    required Future<String> Function(String docId, String name, List<int> data)
        writeFile,
  }) async {
    if (_vaultDir.existsSync()) _vaultDir.deleteSync(recursive: true);
    _vaultDir.createSync(recursive: true);
    await documents.clear();
    await categories.clear();
    await profiles.clear();

    final written = <String, Map<String, String>>{};
    for (final f in files) {
      final path = await writeFile(f.docId, f.name, f.data);
      (written[f.docId] ??= <String, String>{})[f.name] = path;
    }

    for (final raw in (manifest['profiles'] as List? ?? const [])) {
      final m = (raw as Map).cast<String, dynamic>();
      await profiles.put(
        m['id'] as String,
        Profile(
          id: m['id'] as String,
          name: m['name'] as String? ?? 'Me',
          relation: m['relation'] as String? ?? '',
          colorValue: m['color'] as int? ?? 0xFF0F766E,
          iconCodePoint: m['icon'] as int? ?? 0xe7fd,
          isDefault: m['isDefault'] as bool? ?? false,
          createdAt: m['createdAt'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
        ),
      );
    }

    for (final raw in (manifest['categories'] as List? ?? const [])) {
      final m = (raw as Map).cast<String, dynamic>();
      await categories.put(
        m['id'] as String,
        DocCategory(
          id: m['id'] as String,
          name: m['name'] as String? ?? 'Others',
          iconCodePoint: m['icon'] as int? ?? 0xe2c7,
          colorValue: m['color'] as int? ?? 0xFF455A64,
          maskSensitive: m['mask'] as bool? ?? false,
          isBuiltIn: m['builtIn'] as bool? ?? false,
        ),
      );
    }

    DateTime? ms(Object? v) =>
        v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);

    for (final raw in (manifest['documents'] as List? ?? const [])) {
      final m = (raw as Map).cast<String, dynamic>();
      final id = m['id'] as String;
      final names = (m['fileNames'] as List? ?? const []).cast<String>();
      final paths = <String>[
        for (final n in names)
          if (written[id]?[n] != null) written[id]![n]!,
      ];
      await documents.put(
        id,
        DocItem(
          id: id,
          title: m['title'] as String? ?? 'Document',
          categoryId: m['categoryId'] as String? ?? 'other',
          documentNumber: m['documentNumber'] as String? ?? '',
          profileId: m['profileId'] as String? ?? 'me',
          issueDate: ms(m['issueDate']),
          expiryDate: ms(m['expiryDate']),
          notes: m['notes'] as String? ?? '',
          filePaths: paths,
          fileType: DocFileType.values[(m['fileType'] as int?) ?? 0],
          maskByDefault: m['maskByDefault'] as bool? ?? true,
          favorite: m['favorite'] as bool? ?? false,
          createdAt: ms(m['createdAt']),
          updatedAt: ms(m['updatedAt']),
        ),
      );
    }

    final incoming = (manifest['settings'] as Map? ?? const {});
    for (final entry in incoming.entries) {
      await settings.put(entry.key as String, entry.value);
    }

    if (categories.isEmpty) await _seedCategories();
    if (profiles.isEmpty) await _seedProfiles();
  }
}

