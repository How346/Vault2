import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Thrown for any recoverable capture/pick problem so the UI can show a
/// message instead of the app dying.
class CaptureException implements Exception {
  CaptureException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Camera / gallery / file capture with cropping + auto-enhance.
/// Every step happens on-device and never throws an uncaught error.
class FileService {
  FileService._();
  static final FileService instance = FileService._();

  final _picker = ImagePicker();

  /// Android can kill the app while the camera activity is in front.
  /// Call on resume to recover the shot instead of losing it.
  Future<String?> recoverLostCapture() async {
    if (!Platform.isAndroid) return null;
    try {
      final response = await _picker.retrieveLostData();
      if (response.isEmpty || response.file == null) return null;
      return response.file!.path;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _ensureCameraPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    var status = await Permission.camera.status;
    if (status.isGranted || status.isLimited) return true;
    status = await Permission.camera.request();
    if (status.isPermanentlyDenied) {
      throw CaptureException(
          'Camera access is blocked. Enable it in system settings.');
    }
    return status.isGranted || status.isLimited;
  }

  Future<String?> captureFromCamera({bool crop = true, bool enhance = false}) async {
    if (!await _ensureCameraPermission()) {
      throw CaptureException('Camera permission denied.');
    }
    XFile? shot;
    try {
      shot = await _picker.pickImage(
        source: ImageSource.camera,

      );
    } on Exception catch (e) {
      throw CaptureException('Camera could not start (${_short(e)}).');
    }
    if (shot == null) return null;
    return _postProcess(shot.path, crop: crop, enhance: enhance);
  }

  Future<List<String>> pickImages({bool crop = false, bool enhance = false}) async {
    List<XFile> shots;
    try {
      shots = await _picker.pickMultiImage();
    } on Exception catch (e) {
      throw CaptureException('Could not open the gallery (${_short(e)}).');
    }
    final out = <String>[];
    for (final s in shots) {
      final path = await _postProcess(s.path, crop: crop, enhance: enhance);
      if (path != null) out.add(path);
    }
    return out;
  }

  Future<List<String>> pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      );
      return result?.paths.whereType<String>().toList() ?? <String>[];
    } on Exception catch (e) {
      throw CaptureException('Could not open the file picker (${_short(e)}).');
    }
  }

  Future<String?> _postProcess(
    String path, {
    required bool crop,
    required bool enhance,
  }) async {
    var current = path;
    if (crop) {
      final cropped = await _cropSafely(current);
      // A failed/unavailable cropper must not lose the capture.
      if (cropped == _cropCancelled) return null;
      current = cropped ?? current;
    }
    if (enhance) current = await autoEnhance(current);
    return current;
  }

  static const _cropCancelled = '__cancelled__';

  Future<String?> _cropSafely(String path) async {
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: path,
        compressQuality: 100,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop document',
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
          IOSUiSettings(title: 'Crop document'),
        ],
      );
      if (cropped == null) return _cropCancelled;
      return cropped.path;
    } catch (_) {
      // Cropper missing or crashed: keep the original image.
      return null;
    }
  }

  /// Light document clean-up on a background isolate so the UI never janks.
  Future<String> autoEnhance(String path) async {
    try {
      final tmp = await getTemporaryDirectory();
      final target = p.join(
        tmp.path,
        'enh_${DateTime.now().microsecondsSinceEpoch}${p.extension(path).toLowerCase() == '.png' ? '.png' : '.jpg'}',
      );
      final ok = await Isolate.run(() => _enhanceSync(path, target));
      return ok ? target : path;
    } catch (_) {
      return path;
    }
  }

  static bool _enhanceSync(String source, String target) {
    try {
      final bytes = File(source).readAsBytesSync();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return false;

      // Keep the original resolution and use a very light adjustment.
      // Explicit enhancement should never aggressively normalize colours.
      final out = img.adjustColor(
        decoded,
        contrast: 1.04,
        saturation: 1.0,
        gamma: 1.0,
      );

      final ext = p.extension(source).toLowerCase();
      final encoded = ext == '.png'
          ? img.encodePng(out)
          : img.encodeJpg(out, quality: 100);
      File(target).writeAsBytesSync(encoded, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 60 ? '${s.substring(0, 60)}…' : s;
  }

  static bool isPdf(String path) => p.extension(path).toLowerCase() == '.pdf';
}
