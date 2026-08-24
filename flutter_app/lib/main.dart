import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';
import 'state/settings_controller.dart';
import 'state/task_controller.dart';
import 'state/wallet_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await StorageService.instance.init();
  await NotificationService.instance.init();
  await NotificationService.instance.requestPermissions();
  await NotificationService.instance.rescheduleAll();

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
}
