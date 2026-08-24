import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Fields guessed from the scanned pages. Everything happens on-device with
/// ML Kit's bundled model — nothing is uploaded.
class OcrResult {
  const OcrResult({
    this.title,
    this.documentNumber,
    this.issueDate,
    this.expiryDate,
    this.categoryId,
    this.rawText = '',
  });

  final String? title;
  final String? documentNumber;
  final DateTime? issueDate;
  final DateTime? expiryDate;
  final String? categoryId;
  final String rawText;

  bool get isEmpty =>
      documentNumber == null &&
      issueDate == null &&
      expiryDate == null &&
      title == null;
}

class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  TextRecognizer? _recognizer;

  Future<String> readText(List<String> paths) async {
    final buf = StringBuffer();
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    for (final path in paths) {
      if (!File(path).existsSync()) continue;
      if (path.toLowerCase().endsWith('.pdf')) continue;
      try {
        final result =
            await _recognizer!.processImage(InputImage.fromFilePath(path));
        buf.writeln(result.text);
      } catch (_) {
        // A single unreadable page must not break autofill.
      }
    }
    return buf.toString();
  }

  Future<OcrResult> extract(List<String> paths) async {
    final text = await readText(paths);
    if (text.trim().isEmpty) return const OcrResult();
    return parse(text);
  }

  /// Pure text parsing — kept separate so it stays testable.
  static OcrResult parse(String text) {
    final upper = text.toUpperCase();
    String? number;
    String? categoryId;
    String? title;

    final pan = RegExp(r'\b[A-Z]{5}[0-9]{4}[A-Z]\b').firstMatch(upper);
    final aadhaar =
        RegExp(r'\b(\d{4})[\s-]?(\d{4})[\s-]?(\d{4})\b').firstMatch(upper);
    final dl = RegExp(r'\b[A-Z]{2}[\s-]?\d{2}[\s-]?\d{4}[\s-]?\d{5,7}\b')
        .firstMatch(upper);
    final passport = RegExp(r'\b[A-PR-WY][0-9]{7}\b').firstMatch(upper);

    if (upper.contains('INCOME TAX') || upper.contains('PERMANENT ACCOUNT')) {
      categoryId = 'pan';
    } else if (upper.contains('AADHAAR') || upper.contains('UNIQUE IDENTIFICATION')) {
      categoryId = 'aadhaar';
    } else if (upper.contains('DRIVING LICENCE') || upper.contains('DRIVING LICENSE')) {
      categoryId = 'dl';
    } else if (upper.contains('PASSPORT')) {
      categoryId = 'passport';
    } else if (upper.contains('REGISTRATION CERTIFICATE') || upper.contains('CHASSIS')) {
      categoryId = 'rc';
    } else if (upper.contains('POLICY')) {
      categoryId = 'insurance';
    }

    switch (categoryId) {
      case 'pan':
        number = pan?.group(0);
        title = 'PAN Card';
      case 'aadhaar':
        number = aadhaar == null
            ? null
            : '${aadhaar.group(1)} ${aadhaar.group(2)} ${aadhaar.group(3)}';
        title = 'Aadhaar Card';
      case 'dl':
        number = dl?.group(0);
        title = 'Driving Licence';
      case 'passport':
        number = passport?.group(0);
        title = 'Passport';
      case 'rc':
        title = 'Vehicle RC';
      case 'insurance':
        title = 'Insurance Policy';
      default:
        number = pan?.group(0) ??
            (aadhaar == null
                ? null
                : '${aadhaar.group(1)} ${aadhaar.group(2)} ${aadhaar.group(3)}');
    }

    final dates = _dates(upper);
    DateTime? issue, expiry;
    if (dates.isNotEmpty) {
      dates.sort();
      final now = DateTime.now();
      final past = dates.where((d) => d.isBefore(now)).toList();
      final future = dates.where((d) => d.isAfter(now)).toList();
      if (past.isNotEmpty) issue = past.last;
      if (future.isNotEmpty) expiry = future.first;
      if (issue == null && expiry == null) issue = dates.first;
    }

    return OcrResult(
      title: title,
      documentNumber: number,
      issueDate: issue,
      expiryDate: expiry,
      categoryId: categoryId,
      rawText: text,
    );
  }

  static List<DateTime> _dates(String text) {
    final out = <DateTime>[];
    final re = RegExp(r'\b(\d{1,2})[\/\-\.](\d{1,2})[\/\-\.](\d{2,4})\b');
    for (final m in re.allMatches(text)) {
      final d = int.tryParse(m.group(1)!) ?? 0;
      final mo = int.tryParse(m.group(2)!) ?? 0;
      var y = int.tryParse(m.group(3)!) ?? 0;
      if (y < 100) y += y > 50 ? 1900 : 2000;
      if (d < 1 || d > 31 || mo < 1 || mo > 12 || y < 1900 || y > 2100) continue;
      out.add(DateTime(y, mo, d));
    }
    return out;
  }

  Future<void> close() async {
    try {
      await _recognizer?.close();
    } catch (_) {}
    _recognizer = null;
  }
}
