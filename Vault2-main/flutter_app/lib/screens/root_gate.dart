import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/settings_controller.dart';
import 'main_shell.dart';
import 'lock_screen.dart';

/// Root of the app. Swaps between the lock gate and the wallet **in place**
/// instead of pushing routes, so the wallet is always the root route:
/// pressing back on Home simply sends the app to the background (no black
/// screen from popping the last route).
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> with WidgetsBindingObserver {
  bool _unlocked = false;
  int _lockSession = 0;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_unlocked) return;
    if (!context.read<SettingsController>().appLockEnabled) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final away = _backgroundedAt;
      _backgroundedAt = null;
      // Re-lock only after a real absence, so the camera / file picker
      // round-trip never kicks the user back to the PIN pad.
      if (away != null &&
          DateTime.now().difference(away) > const Duration(seconds: 45)) {
        setState(() {
          _unlocked = false;
          _lockSession++;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked =
        context.watch<SettingsController>().appLockEnabled && !_unlocked;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      // A coloured backdrop keeps the cross-fade from ever showing black.
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
          ...previous,
          if (current != null) current,
        ],
      ),
      child: locked
          ? LockScreen(
              key: ValueKey('lock_$_lockSession'),
              onUnlocked: () => setState(() => _unlocked = true),
            )
          : const MainShell(key: ValueKey('home')),
    );
  }
}
