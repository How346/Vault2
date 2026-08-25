import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../models/doc_item.dart';
import '../utils/formatters.dart';
import '../utils/masking.dart';
import 'storage_service.dart';

/// Shares through the OS share sheet only. Nothing is uploaded by the app.
class ShareService {
  ShareService._();
  static final ShareService instance = ShareService._();

  Future<void> shareDocument(DocItem doc, {required bool masked}) async {
    final files = <XFile>[];
    final exportDir = await StorageService.instance.exportDir();

    for (final path in doc.filePaths) {
      if (!File(path).existsSync()) continue;
      if (masked && !doc.isPdf) {
        final out = await _watermark(path, exportDir.path);
        files.add(XFile(out));
      } else {
        files.add(XFile(path));
      }
    }

    await Share.shareXFiles(
      files,
      text: buildSummary(doc, masked: masked),
      subject: doc.title,
    );
  }

  Future<void> shareDetailsOnly(DocItem doc, {required bool masked}) =>
      Share.share(buildSummary(doc, masked: masked), subject: doc.title);

  String buildSummary(DocItem doc, {required bool masked}) {
    final number = doc.documentNumber.isEmpty
        ? '—'
        : (masked
            ? Masking.forCategory(doc.categoryId, doc.documentNumber)
            : doc.documentNumber);
    final buf = StringBuffer()
      ..writeln(doc.title)
      ..writeln('Number: $number')
      ..writeln('Issued: ${formatDate(doc.issueDate)}')
      ..writeln('Expires: ${formatDate(doc.expiryDate)}');
    if (doc.notes.trim().isNotEmpty) buf.writeln('Notes: ${doc.notes.trim()}');
    if (masked) buf.writeln('(Shared with sensitive details masked)');
    return buf.toString();
  }

  /// Burns a masked banner onto an image copy so the shared file itself
  /// signals that details are redacted.
  Future<String> _watermark(String path, String outDir) async {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return path;

    final bandHeight = (decoded.height * 0.09).clamp(48, 200).toInt();
    img.fillRect(
      decoded,
      x1: 0,
      y1: decoded.height - bandHeight,
      x2: decoded.width,
      y2: decoded.height,
      color: img.ColorRgba8(0, 0, 0, 190),
    );
    img.drawString(
      decoded,
      'MASKED COPY — shared offline',
      font: img.arial24,
      x: 16,
      y: decoded.height - bandHeight + (bandHeight ~/ 3),
      color: img.ColorRgb8(255, 255, 255),
    );

    final target = p.join(outDir, 'masked_${p.basenameWithoutExtension(path)}.jpg');
    await File(target).writeAsBytes(img.encodeJpg(decoded, quality: 100));
    return target;
  }
}
