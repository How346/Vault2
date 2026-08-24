import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/root_gate.dart';
import 'state/settings_controller.dart';
import 'theme.dart';

class DocWalletApp extends StatelessWidget {
  const DocWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return MaterialApp(
      title: 'Wallet',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const RootGate(),
      builder: (context, child) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: Theme.of(context).brightness == Brightness.light
              ? AppGradients.background
              : null,
          color: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).scaffoldBackgroundColor
              : null,
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
