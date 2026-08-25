import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

/// Server/marketing push notifications via OneSignal (backed by Firebase
/// Cloud Messaging on Android).
///
/// This is separate and independent from [NotificationService]: that one
/// schedules local, on-device reminders (due dates, the overdue timer) and
/// needs no network or backend. This service only handles notifications
/// that are *sent to* the device from OneSignal's dashboard or REST API.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  static const String _oneSignalAppId =
      'f931f760-d9ae-460d-a8b6-0f6aba64692d';

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (kDebugMode) {
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    }

    OneSignal.initialize(_oneSignalAppId);

    // Ask the user for notification permission (Android 13+ requires this
    // explicitly; iOS always requires it). Safe to call even if the app's
    // own local-reminder permission request already ran — the OS
    // deduplicates the system prompt.
    await OneSignal.Notifications.requestPermission(true);
  }

  /// OneSignal's per-device id — useful once you want to target a specific
  /// installation from your backend / the OneSignal dashboard.
  Future<String?> getPlayerId() async {
    return OneSignal.User.pushSubscription.id;
  }

  /// Tag this device/user so pushes can be targeted (e.g. by profile id).
  /// Call this after the user picks/creates their profile.
  Future<void> setExternalUserId(String id) async {
    await OneSignal.login(id);
  }

  Future<void> clearExternalUserId() async {
    await OneSignal.logout();
  }
}
