import 'package:flutter/foundation.dart';

import 'push_service.dart';

/// Compatibility facade for the old Firebase notification service.
///
/// This project uses OneSignal for remote push notifications. OneSignal
/// uses Firebase Cloud Messaging internally on Android, so the Flutter
/// project must not depend on firebase_core or firebase_messaging merely to
/// receive OneSignal pushes.
///
/// Keep this class only for compatibility with older code that may still
/// reference FirebaseService. All remote-push work is delegated to
/// PushService.
class FirebaseService {
  FirebaseService._();

  static final FirebaseService instance = FirebaseService._();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    try {
      await PushService.instance.init();
      _initialized = true;
    } catch (error, stackTrace) {
      debugPrint('Push notification initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<String?> getToken() async {
    await init();
    try {
      return await PushService.instance.getPlayerId();
    } catch (error) {
      debugPrint('Could not get push subscription ID: $error');
      return null;
    }
  }

  Future<String?> getPlayerId() => getToken();

  Future<void> setUserId(String id) async {
    final value = id.trim();
    if (value.isEmpty) return;

    await init();
    try {
      await PushService.instance.setExternalUserId(value);
    } catch (error, stackTrace) {
      debugPrint('Could not set push user ID: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> clearUserId() async {
    await init();
    try {
      await PushService.instance.clearExternalUserId();
    } catch (error, stackTrace) {
      debugPrint('Could not clear push user ID: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
