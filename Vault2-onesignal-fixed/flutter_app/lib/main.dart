import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/notification_service.dart';
import 'services/push_service.dart';
import 'services/storage_service.dart';
import 'state/settings_controller.dart';
import 'state/task_controller.dart';
import 'state/wallet_controller.dart';

final class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(NotificationService.instance.onAppResumed());
    }
  }
}

final _appLifecycleObserver = _AppLifecycleObserver();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(
    [DeviceOrientation.portraitUp],
  );

  // Storage must be ready before providers are created because their
  // getters access Hive boxes. Notification setup must NOT block the first
  // Flutter frame: a native notification/plugin problem should never leave
  // the user staring at a white screen.
  await StorageService.instance.init();

  WidgetsBinding.instance.addObserver(_appLifecycleObserver);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsController()),
        ChangeNotifierProvider(create: (_) => WalletController()),
        ChangeNotifierProvider(create: (_) => TaskController()),
      ],
      child: const DocWalletApp(),
    ),
  );

  // Notification initialization and rescheduling happen after the first
  // frame. Every operation is isolated so a notification/OEM/plugin error
  // cannot crash or prevent the app UI from opening.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initializeNotifications());
    unawaited(_initializePush());
  });
}

Future<void> _initializePush() async {
  try {
    await PushService.instance.init();
  } catch (error, stackTrace) {
    // Same rule as local notifications: a push/network/plugin problem must
    // never prevent the wallet UI from starting or working offline.
    debugPrint('Push initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

Future<void> _initializeNotifications() async {
  try {
    await NotificationService.instance.init();
    await NotificationService.instance.requestPermissions();
    await NotificationService.instance.rescheduleStoredNotifications();
  } catch (error, stackTrace) {
    // Notification delivery must never prevent the wallet UI from starting.
    debugPrint('Notification initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
