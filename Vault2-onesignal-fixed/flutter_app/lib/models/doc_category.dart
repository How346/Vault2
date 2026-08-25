import 'package:hive/hive.dart';

/// typeId 1
class DocCategory extends HiveObject {
  final String id;
  String name;
  int iconCodePoint;
  int colorValue;
  bool maskSensitive;
  bool isBuiltIn;

  DocCategory({
    required this.id,
    required this.name,
    required this.iconCodePoint,
    required this.colorValue,
    this.maskSensitive = false,
    this.isBuiltIn = false,
  });
}

class DocCategoryAdapter extends TypeAdapter<DocCategory> {
  @override
  final int typeId = 1;

  @override
  DocCategory read(BinaryReader reader) {
    final fields = reader.readMap().cast<String, dynamic>();
    return DocCategory(
      id: fields['id'] as String,
      name: fields['name'] as String,
      iconCodePoint: fields['icon'] as int,
      colorValue: fields['color'] as int,
      maskSensitive: fields['mask'] as bool? ?? false,
      isBuiltIn: fields['builtIn'] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, DocCategory obj) {
    writer.writeMap(<String, dynamic>{
      'id': obj.id,
      'name': obj.name,
      'icon': obj.iconCodePoint,
      'color': obj.colorValue,
      'mask': obj.maskSensitive,
      'builtIn': obj.isBuiltIn,
    });
  }
}
