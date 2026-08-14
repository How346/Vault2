import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/notification_service.dart';
import '../services/security_service.dart';
import '../services/storage_service.dart';
import '../state/settings_controller.dart';
import '../state/wallet_controller.dart';
import 'transfer_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final wallet = context.read<WalletController>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _Header('Appearance'),
          Card(
            child: Column(
              children: ThemeMode.values.map((mode) {
                return RadioListTile<ThemeMode>(
                  value: mode,
                  // ignore: deprecated_member_use
                  groupValue: settings.themeMode,
                  // ignore: deprecated_member_use
                  onChanged: (value) {
                    if (value != null) {
                      settings.setThemeMode(value);
                    }
                  },
                  title: Text(switch (mode) {
                    ThemeMode.system => 'Follow system',
                    ThemeMode.light => 'Light',
                    ThemeMode.dark => 'Dark',
                  }),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 18),
          const _Header('Privacy & security'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: settings.appLockEnabled,
                  onChanged: (v) async {
                    await settings.setAppLockEnabled(v);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(v
                            ? 'App lock on — you will set a PIN next launch'
                            : 'App lock off — PIN removed'),
                      ));
                    }
                  },
                  title: const Text('App lock'),
                  subtitle: const Text('Require PIN / biometric to open Wallet'),
                ),
                SwitchListTile(
                  value: settings.biometricEnabled,
                  onChanged:
                      settings.appLockEnabled ? settings.setBiometricEnabled : null,
                  title: const Text('Biometric unlock'),
                  subtitle: const Text('Fingerprint or Face ID at launch'),
                ),
                SwitchListTile(
                  value: settings.maskByDefault,
                  onChanged: settings.setMaskByDefault,
                  title: const Text('Mask numbers by default'),
                  subtitle: const Text('Applies to new documents'),
                ),

                ListTile(
                  leading: const Icon(Icons.password_rounded),
                  title: const Text('Change PIN'),
                  onTap: () => _changePin(context),
                ),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('Clear share cache'),
                  subtitle: const Text('Removes temporary masked copies'),
                  onTap: () async {
                    await StorageService.instance.clearExports();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Share cache cleared')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const _Header('Reminders'),
          Card(
            child: FutureBuilder<bool>(
              future: NotificationService.instance.exactAlarmPermissionGranted(),
              builder: (context, snapshot) {
                final exact = snapshot.data == true;
                return ListTile(
                  onTap: exact ? null : () => NotificationService.instance.openExactAlarmSettings(),
                  leading: Icon(
                    exact
                        ? Icons.verified_rounded
                        : Icons.schedule_outlined,
                    color: exact ? scheme.primary : scheme.error,
                  ),
                  title: Text(
                    exact ? 'Precise reminders ready' : 'Precise reminders need access',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    exact
                        ? 'Exact alarms are allowed for on-time reminders.'
                        : 'Enable Alarms & reminders so Wallet can alert you at the selected minute.',
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Enable precise reminders'),
              subtitle: const Text(
                'Allow notifications and exact alarms so reminders fire at the selected minute.',
              ),
              onTap: () async {
                final ready = await NotificationService.instance
                    .ensureReminderAccess(openSettings: true);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ready
                          ? 'Precise reminders are enabled.'
                          : 'Android Settings opened. Turn on “Allow setting alarms and reminders” for Wallet, then return here.',
                    ),
                    duration: const Duration(seconds: 6),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notification_add_outlined),
              title: const Text('Test notification'),
              subtitle: const Text('Show a notification now'),
              onTap: () async {
                try {
                  final shown =
                      await NotificationService.instance.showTestNotification();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        shown
                            ? 'Test notification sent. Check your notification tray.'
                            : 'Notifications are blocked for Wallet. Enable notifications in Android Settings and try again.',
                      ),
                      duration: const Duration(seconds: 4),
                    ),
                  );
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Notification test failed: $error'),
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 18),
          const _Header('Move to a new phone'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.phonelink_setup_rounded),
              title: const Text('Offline data transfer'),
              subtitle: const Text('Send or receive everything over Wi-Fi, no internet'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TransferScreen()),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const _Header('Danger zone'),
          Card(
            color: scheme.errorContainer,
            child: ListTile(
              leading: Icon(Icons.delete_forever_rounded, color: scheme.onErrorContainer),
              title: Text('Erase all data',
                  style: TextStyle(color: scheme.onErrorContainer)),
              subtitle: Text('Deletes every document and file',
                  style: TextStyle(color: scheme.onErrorContainer)),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Erase everything?'),
                    content: const Text('This cannot be undone.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Erase')),
                    ],
                  ),
                );
                if (ok == true) await wallet.wipeAll();
              },
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Wallet works fully offline.\nNo servers, no analytics, no accounts.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changePin(BuildContext context) async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final settings = context.read<SettingsController>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              decoration: const InputDecoration(labelText: 'Current PIN'),
            ),
            TextField(
              controller: newCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              decoration: const InputDecoration(labelText: 'New 4-digit PIN'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    if (ok == true) {
      final valid = await SecurityService.instance.verifyPin(currentCtrl.text);
      String message;
      if (!valid) {
        message = 'Current PIN is incorrect';
      } else if (newCtrl.text.length != 4) {
        message = 'New PIN must be 4 digits';
      } else {
        await settings.setPin(newCtrl.text);
        message = 'PIN updated';
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    }
    currentCtrl.dispose();
    newCtrl.dispose();
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      );
}
