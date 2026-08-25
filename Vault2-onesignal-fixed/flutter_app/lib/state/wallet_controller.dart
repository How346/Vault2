import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/doc_category.dart';
import '../models/doc_item.dart';
import '../models/profile.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';

enum DocSort { recent, title, expiry }

class WalletController extends ChangeNotifier {
  final _storage = StorageService.instance;

  /// Rebuilds every listener after bulk changes (e.g. offline device import).
  void refresh() => notifyListeners();


  String _query = '';
  String get query => _query;

  DocSort _sort = DocSort.recent;
  DocSort get sort => _sort;

  void setSort(DocSort value) {
    _sort = value;
    notifyListeners();
  }

  void search(String value) {
    _query = value;
    notifyListeners();
  }

  // ---------------------------------------------------------------- profiles

  List<Profile> get profiles {
    final list = _storage.profiles.values.toList()
      ..sort((a, b) => a.isDefault == b.isDefault
          ? a.createdAt.compareTo(b.createdAt)
          : (a.isDefault ? -1 : 1));
    return list;
  }

  String get activeProfileId {
    final saved =
        _storage.settings.get(SettingsKeys.activeProfile) as String?;
    if (saved != null && _storage.profiles.containsKey(saved)) return saved;
    return profiles.isEmpty ? 'me' : profiles.first.id;
  }

  Profile? get activeProfile => _storage.profiles.get(activeProfileId);

  Profile? profile(String id) => _storage.profiles.get(id);

  Future<void> setActiveProfile(String id) async {
    await _storage.settings.put(SettingsKeys.activeProfile, id);
    notifyListeners();
  }

  Future<Profile> addProfile({
    required String name,
    String relation = '',
    int colorValue = 0xFF0F766E,
    int iconCodePoint = 0xe7fd,
  }) async {
    final id = 'p-${newId()}';
    final profile = Profile(
      id: id,
      name: name,
      relation: relation,
      colorValue: colorValue,
      iconCodePoint: iconCodePoint,
    );
    await _storage.profiles.put(id, profile);
    notifyListeners();
    return profile;
  }

  Future<void> updateProfile(
    Profile profile, {
    String? name,
    String? relation,
    int? colorValue,
  }) async {
    if (name != null && name.trim().isNotEmpty) profile.name = name.trim();
    if (relation != null) profile.relation = relation.trim();
    if (colorValue != null) profile.colorValue = colorValue;
    await profile.save();
    notifyListeners();
  }

  /// Deletes a profile and every document that belongs to it.
  Future<void> deleteProfile(Profile profile) async {
    if (profile.isDefault) return;
    for (final doc in _storage.documents.values
        .where((d) => d.profileId == profile.id)
        .toList()) {
      await deleteDocument(doc, silent: true);
    }
    await _storage.profiles.delete(profile.id);
    if (activeProfileId == profile.id) {
      await _storage.settings.put(SettingsKeys.activeProfile, 'me');
    }
    notifyListeners();
  }

  int documentCountForProfile(String profileId) => _storage.documents.values
      .where((d) => d.profileId == profileId)
      .length;

  // -------------------------------------------------------------- categories

  List<DocCategory> get categories => _storage.categories.values.toList()
    ..sort((a, b) => a.isBuiltIn == b.isBuiltIn
        ? a.name.compareTo(b.name)
        : (a.isBuiltIn ? -1 : 1));

  DocCategory? category(String id) => _storage.categories.get(id);

  // --------------------------------------------------------------- documents

  /// Documents of the active profile, filtered by the search query.
  List<DocItem> get allDocuments {
    final active = activeProfileId;
    final list = _storage.documents.values
        .where((d) => d.profileId == active)
        .toList();
    _applySort(list);
    if (_query.trim().isEmpty) return list;
    final q = _query.toLowerCase();
    return list
        .where((d) =>
            d.title.toLowerCase().contains(q) ||
            d.documentNumber.toLowerCase().contains(q) ||
            d.notes.toLowerCase().contains(q))
        .toList();
  }

  void _applySort(List<DocItem> list) {
    switch (_sort) {
      case DocSort.recent:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case DocSort.title:
        list.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case DocSort.expiry:
        list.sort((a, b) {
          final ax = a.expiryDate, bx = b.expiryDate;
          if (ax == null && bx == null) return 0;
          if (ax == null) return 1;
          if (bx == null) return -1;
          return ax.compareTo(bx);
        });
    }
    list.sort((a, b) => (b.favorite ? 1 : 0).compareTo(a.favorite ? 1 : 0));
  }

  DocItem? docById(String id) => _storage.documents.get(id);

  List<DocItem> documentsIn(String categoryId) =>
      allDocuments.where((d) => d.categoryId == categoryId).toList();

  int countIn(String categoryId) => _storage.documents.values
      .where((d) => d.categoryId == categoryId && d.profileId == activeProfileId)
      .length;

  /// Expiring documents across every profile so nothing is missed.
  List<DocItem> get expiringSoon {
    final list = _storage.documents.values.where((d) {
      final days = daysUntil(d.expiryDate);
      return days != null && days <= 60;
    }).toList()
      ..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));
    return list;
  }

  List<DocItem> get favorites => allDocuments.where((d) => d.favorite).toList();

  String newId() {
    final rnd = Random();
    return '${DateTime.now().millisecondsSinceEpoch}-${rnd.nextInt(99999)}';
  }

  /// Copies [sourcePaths] into private storage, then saves the record.
  Future<DocItem> saveDocument({
    required DocItem draft,
    required List<String> sourcePaths,
  }) async {
    final imported = <String>[];
    for (final src in sourcePaths) {
      if (!File(src).existsSync()) continue;
      imported.add(await _storage.importFile(src, docId: draft.id));
    }
    draft.filePaths = [...draft.filePaths, ...imported];
    draft.fileType = draft.filePaths.any((f) => f.toLowerCase().endsWith('.pdf'))
        ? DocFileType.pdf
        : DocFileType.image;
    draft.updatedAt = DateTime.now();

    // Persist the document first so a notification/OEM scheduling problem can
    // never cause a successfully imported file to disappear.
    draft.reminderIds = const [];
    await _storage.documents.put(draft.id, draft);

    try {
      // Android 13+ blocks delivery until POST_NOTIFICATIONS is granted.
      await NotificationService.instance.requestPermissions(requestExactAlarm: true);
      draft.reminderIds =
          await NotificationService.instance.scheduleExpiry(draft);
      await draft.save();
    } catch (_) {
      // The document remains safely stored even if the OS temporarily rejects
      // a schedule. The next edit/save will retry scheduling.
      draft.reminderIds = const [];
      await draft.save();
    }

    notifyListeners();
    return draft;
  }

  Future<void> moveToProfile(DocItem doc, String profileId) async {
    doc.profileId = profileId;
    doc.updatedAt = DateTime.now();
    await doc.save();
    notifyListeners();
  }

  Future<void> toggleFavorite(DocItem doc) async {
    doc.favorite = !doc.favorite;
    doc.updatedAt = DateTime.now();
    await doc.save();
    notifyListeners();
  }

  Future<void> toggleMask(DocItem doc) async {
    doc.maskByDefault = !doc.maskByDefault;
    await doc.save();
    notifyListeners();
  }

  Future<void> deleteDocument(DocItem doc, {bool silent = false}) async {
    try {
      await NotificationService.instance.cancelFor(doc);
    } catch (_) {}
    await _storage.deleteDocFiles(doc);
    await _storage.documents.delete(doc.id);
    if (!silent) notifyListeners();
  }

  Future<void> addCategory({
    required String name,
    required int iconCodePoint,
    required int colorValue,
    bool maskSensitive = false,
  }) async {
    final id = 'custom-${newId()}';
    await _storage.categories.put(
      id,
      DocCategory(
        id: id,
        name: name,
        iconCodePoint: iconCodePoint,
        colorValue: colorValue,
        maskSensitive: maskSensitive,
      ),
    );
    notifyListeners();
  }

  Future<void> deleteCategory(DocCategory category) async {
    if (category.isBuiltIn) return;
    for (final doc in _storage.documents.values
        .where((d) => d.categoryId == category.id)
        .toList()) {
      doc.categoryId = 'other';
      await doc.save();
    }
    await _storage.categories.delete(category.id);
    notifyListeners();
  }

  Future<void> wipeAll() async {
    for (final doc in _storage.documents.values) {
      try {
        await NotificationService.instance.cancelFor(doc);
      } catch (_) {}
    }
    await _storage.wipeEverything();
    notifyListeners();
  }
}
