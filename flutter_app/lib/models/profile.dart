import 'package:hive/hive.dart';

/// A wallet owner (self, spouse, child, ...). Documents belong to one profile.
/// typeId 3
class Profile extends HiveObject {
  final String id;
  String name;
  String relation;
  int colorValue;
  int iconCodePoint;
  bool isDefault;
  DateTime createdAt;

  Profile({
    required this.id,
    required this.name,
    this.relation = '',
    this.colorValue = 0xFF0F766E,
    this.iconCodePoint = 0xe7fd,
    this.isDefault = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    String head(String s) => s.substring(0, 1).toUpperCase();
    if (parts.length == 1) return head(parts.first);
    return '${head(parts.first)}${head(parts.last)}';
  }
}

class ProfileAdapter extends TypeAdapter<Profile> {
  @override
  final int typeId = 3;

  @override
  Profile read(BinaryReader reader) {
    final m = reader.readMap().cast<String, dynamic>();
    return Profile(
      id: m['id'] as String,
      name: m['name'] as String? ?? 'Me',
      relation: m['relation'] as String? ?? '',
      colorValue: m['color'] as int? ?? 0xFF0F766E,
      iconCodePoint: m['icon'] as int? ?? 0xe7fd,
      isDefault: m['isDefault'] as bool? ?? false,
      createdAt: m['createdAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
    );
  }

  @override
  void write(BinaryWriter writer, Profile o) {
    writer.writeMap(<String, dynamic>{
      'id': o.id,
      'name': o.name,
      'relation': o.relation,
      'color': o.colorValue,
      'icon': o.iconCodePoint,
      'isDefault': o.isDefault,
      'createdAt': o.createdAt.millisecondsSinceEpoch,
    });
  }
}
