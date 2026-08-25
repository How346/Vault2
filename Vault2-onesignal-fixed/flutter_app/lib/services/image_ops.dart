import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Filters offered by the smart camera / crop screen.
enum ScanFilter { original, enhance, blackWhite, punch }

extension ScanFilterX on ScanFilter {
  String get label => switch (this) {
        ScanFilter.original => 'Original',
        ScanFilter.enhance => 'Auto',
        ScanFilter.blackWhite => 'B & W',
        ScanFilter.punch => 'Punch',
      };
}

/// Pure-Dart image pipeline: perspective warp + rotation + filters.
/// Everything runs on a background isolate so the UI never janks.
class ImageOps {
  const ImageOps._();

  /// [quad] is 8 normalised values (0..1): tlX, tlY, trX, trY, brX, brY, blX, blY.
  /// Pass null to skip the perspective correction.
  static Future<String?> process({
    required String source,
    List<double>? quad,
    int quarterTurns = 0,
    ScanFilter filter = ScanFilter.enhance,
  }) async {
    try {
      final tmp = await getTemporaryDirectory();
      final target = p.join(
        tmp.path,
        'scan_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      final ok = await Isolate.run(
        () => _processSync(source, target, quad, quarterTurns, filter.index),
      );
      return ok ? target : source;
    } catch (_) {
      return source;
    }
  }

  static bool _processSync(
    String source,
    String target,
    List<double>? quad,
    int quarterTurns,
    int filterIndex,
  ) {
    try {
      final bytes = File(source).readAsBytesSync();
      final filter = ScanFilter.values[filterIndex];

      // "Original" must really mean original. Do not decode/re-encode a
      // gallery image just to display/save it; that causes JPEG generation
      // loss and can change colours.
      if (filter == ScanFilter.original &&
          (quad == null || quad.length != 8) &&
          quarterTurns % 4 == 0) {
        File(target).writeAsBytesSync(bytes, flush: true);
        return true;
      }

      final decoded = img.decodeImage(bytes);
      if (decoded == null) return false;

      var out = img.bakeOrientation(decoded);

      if (quad != null && quad.length == 8) {
        out = _warp(out, quad);
      }

      if (quarterTurns % 4 != 0) {
        out = img.copyRotate(
          out,
          angle: (quarterTurns % 4) * 90,
        );
      }

      switch (filter) {
        case ScanFilter.original:
          // No colour manipulation.
          break;
        case ScanFilter.enhance:
          // Gentle enhancement only; preserve document colours instead of
          // normalising every channel and shifting the original palette.
          out = img.adjustColor(
            out,
            contrast: 1.06,
            saturation: 1.0,
            gamma: 1.0,
          );
        case ScanFilter.blackWhite:
          out = img.grayscale(out);
          out = img.adjustColor(
            out,
            contrast: 1.35,
            brightness: 1.02,
          );
        case ScanFilter.punch:
          out = img.adjustColor(
            out,
            contrast: 1.08,
            saturation: 1.05,
          );
      }

      // Never downscale a user's document. Re-encoded scan output uses the
      // highest practical JPEG quality to minimise generation loss.
      File(target).writeAsBytesSync(
        img.encodeJpg(out, quality: 100),
        flush: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Bilinear quad -> rectangle mapping. Straightens the document and removes
  /// the perspective skew introduced by holding the phone at an angle.
  static img.Image _warp(img.Image src, List<double> q) {
    final w = src.width.toDouble(), h = src.height.toDouble();
    final xs = [q[0] * w, q[2] * w, q[4] * w, q[6] * w];
    final ys = [q[1] * h, q[3] * h, q[5] * h, q[7] * h];

    double dist(int a, int b) =>
        math.sqrt(math.pow(xs[a] - xs[b], 2) + math.pow(ys[a] - ys[b], 2));

    final outW = math.max(dist(0, 1), dist(3, 2)).round().clamp(64, src.width);
    final outH = math.max(dist(0, 3), dist(1, 2)).round().clamp(64, src.height);
    final out = img.Image(width: outW, height: outH);

    for (var y = 0; y < outH; y++) {
      final v = y / (outH - 1);
      for (var x = 0; x < outW; x++) {
        final u = x / (outW - 1);
        final sx = (1 - v) * (xs[0] + (xs[1] - xs[0]) * u) +
            v * (xs[3] + (xs[2] - xs[3]) * u);
        final sy = (1 - v) * (ys[0] + (ys[1] - ys[0]) * u) +
            v * (ys[3] + (ys[2] - ys[3]) * u);
        final px = sx.round().clamp(0, src.width - 1);
        final py = sy.round().clamp(0, src.height - 1);
        out.setPixel(x, y, src.getPixel(px, py));
      }
    }
    return out;
  }

  /// Very cheap document-edge finder used for the live camera overlay.
  /// Works on the luminance plane of a camera frame and returns a normalised
  /// rect (left, top, right, bottom) or null when nothing convincing is found.
  static List<double>? detectEdgesSync(
    Uint8List luma,
    int width,
    int height,
    int bytesPerRow,
  ) {
    try {
      const grid = 96;
      final stepX = math.max(1, width ~/ grid);
      final stepY = math.max(1, height ~/ grid);
      final cols = width ~/ stepX;
      final rows = height ~/ stepY;
      if (cols < 8 || rows < 8) return null;

      final small = Uint8List(cols * rows);
      for (var r = 0; r < rows; r++) {
        final srcRow = r * stepY * bytesPerRow;
        for (var c = 0; c < cols; c++) {
          final i = srcRow + c * stepX;
          small[r * cols + c] = i < luma.length ? luma[i] : 0;
        }
      }

      final rowEnergy = List<double>.filled(rows, 0);
      final colEnergy = List<double>.filled(cols, 0);
      for (var r = 1; r < rows - 1; r++) {
        for (var c = 1; c < cols - 1; c++) {
          final v = small[r * cols + c];
          final gx = (small[r * cols + c + 1] - v).abs();
          final gy = (small[(r + 1) * cols + c] - v).abs();
          final g = (gx + gy).toDouble();
          if (g > 18) {
            rowEnergy[r] += g;
            colEnergy[c] += g;
          }
        }
      }

      double maxOf(List<double> l) => l.reduce(math.max);
      final rowMax = maxOf(rowEnergy), colMax = maxOf(colEnergy);
      if (rowMax < 250 || colMax < 250) return null;

      int first(List<double> l, double t) {
        for (var i = 0; i < l.length; i++) {
          if (l[i] > t) return i;
        }
        return -1;
      }

      int last(List<double> l, double t) {
        for (var i = l.length - 1; i >= 0; i--) {
          if (l[i] > t) return i;
        }
        return -1;
      }

      final top = first(rowEnergy, rowMax * 0.22);
      final bottom = last(rowEnergy, rowMax * 0.22);
      final left = first(colEnergy, colMax * 0.22);
      final right = last(colEnergy, colMax * 0.22);
      if (top < 0 || bottom <= top || left < 0 || right <= left) return null;

      final l = left / cols, t = top / rows, r = right / cols, b = bottom / rows;
      if ((r - l) < 0.22 || (b - t) < 0.14) return null;
      return [l, t, r, b];
    } catch (_) {
      return null;
    }
  }
}
