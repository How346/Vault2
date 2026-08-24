import 'package:hive/hive.dart';

enum DocFileType { image, pdf, other }

/// typeId 2
class DocItem extends HiveObject {
  final String id;
  String title;
  String categoryId;
  String documentNumber;
  String profileId;
  DateTime? issueDate;
  DateTime? expiryDate;
  String notes;

  /// Absolute paths inside the app-private documents directory.
  List<String> filePaths;
  DocFileType fileType;

  bool maskByDefault;
  bool favorite;
  DateTime createdAt;
  DateTime updatedAt;

  /// Notification ids scheduled for this doc, so they can be cancelled.
  List<int> reminderIds;

  DocItem({
    required this.id,
    required this.title,
    required this.categoryId,
    this.documentNumber = '',
    this.profileId = 'me',
    this.issueDate,
    this.expiryDate,
    this.notes = '',
    List<String>? filePaths,
    this.fileType = DocFileType.image,
    this.maskByDefault = true,
    this.favorite = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<int>? reminderIds,
  })  : filePaths = filePaths ?? <String>[],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        reminderIds = reminderIds ?? <int>[];

  String? get primaryPath => filePaths.isEmpty ? null : filePaths.first;
  bool get isPdf => fileType == DocFileType.pdf;
}

class DocItemAdapter extends TypeAdapter<DocItem> {
  @override
  final int typeId = 2;

  @override
  DocItem read(BinaryReader reader) {
    final m = reader.readMap().cast<String, dynamic>();
    DateTime? dt(String k) {
      final v = m[k];
      return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);
    }

    return DocItem(
      id: m['id'] as String,
      title: m['title'] as String,
      categoryId: m['categoryId'] as String,
      documentNumber: m['documentNumber'] as String? ?? '',
      profileId: m['profileId'] as String? ?? 'me',
      issueDate: dt('issueDate'),
      expiryDate: dt('expiryDate'),
      notes: m['notes'] as String? ?? '',
      filePaths: (m['filePaths'] as List?)?.cast<String>() ?? <String>[],
      fileType: DocFileType.values[(m['fileType'] as int?) ?? 0],
      maskByDefault: m['maskByDefault'] as bool? ?? true,
      favorite: m['favorite'] as bool? ?? false,
      createdAt: dt('createdAt') ?? DateTime.now(),
      updatedAt: dt('updatedAt') ?? DateTime.now(),
      reminderIds: (m['reminderIds'] as List?)?.cast<int>() ?? <int>[],
    );
  }

  @override
  void write(BinaryWriter writer, DocItem o) {
    writer.writeMap(<String, dynamic>{
      'id': o.id,
      'title': o.title,
      'categoryId': o.categoryId,
      'documentNumber': o.documentNumber,
      'profileId': o.profileId,
      'issueDate': o.issueDate?.millisecondsSinceEpoch,
      'expiryDate': o.expiryDate?.millisecondsSinceEpoch,
      'notes': o.notes,
      'filePaths': o.filePaths,
      'fileType': o.fileType.index,
      'maskByDefault': o.maskByDefault,
      'favorite': o.favorite,
      'createdAt': o.createdAt.millisecondsSinceEpoch,
      'updatedAt': o.updatedAt.millisecondsSinceEpoch,
      'reminderIds': o.reminderIds,
    });
  }
}
