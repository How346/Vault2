import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    debugPrint('FCM background message: ${message.messageId}');
  } catch (error, stackTrace) {
    debugPrint('FCM background handler failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

/// Firebase Cloud Messaging integration for Wallet.
///
/// Firebase configuration is loaded from android/app/google-services.json.
/// The service is intentionally isolated so a Firebase/network failure can
/// never prevent the offline wallet UI from opening.
class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) {
      debugPrint('FCM registration token: $token');
    }

    messaging.onTokenRefresh.listen((newToken) {
      debugPrint('FCM token refreshed: $newToken');
    });

    FirebaseMessaging.onMessage.listen((message) {
      unawaited(_showForegroundMessage(message));
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('FCM notification opened: ${message.messageId}');
    });

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('FCM launched app from notification: ${initialMessage.messageId}');
    }

    _initialized = true;
  }

  Future<void> _showForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title']?.toString();
    final body = notification?.body ?? message.data['body']?.toString();
    if (title == null && body == null) return;

    try {
      await NotificationService.instance.showRemoteMessage(
        title: title ?? 'Wallet',
        body: body ?? '',
        payload: message.messageId,
      );
    } catch (error, stackTrace) {
      debugPrint('Could not show foreground FCM notification: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
