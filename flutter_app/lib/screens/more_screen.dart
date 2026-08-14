import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/storage_service.dart';
import '../state/settings_controller.dart';
import '../state/wallet_controller.dart';
import '../widgets/brand.dart';
import 'about_screen.dart';
import 'documents_screen.dart';
import 'profiles_screen.dart';
import 'settings_screen.dart';
import 'transfer_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    final settings = context.watch<SettingsController>();
    final scheme = Theme.of(context).colorScheme;
    final profile = wallet.activeProfile;

    void go(Widget page) => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => page),
        );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 130),
        children: [
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: scheme.primary,
                child: Text(
                  profile?.initials ?? 'M',
                  style: TextStyle(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 17),
                ),
              ),
              title: Text(profile?.name ?? 'Me',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16)),
              subtitle: const Text('Manage your account and preferences'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => go(const ProfilesScreen()),
            ),
          ),
          const _GroupTitle('Manage'),
          _Group(children: [
            _Row(
              icon: Icons.people_alt_outlined,
              label: 'Profiles',
              onTap: () => go(const ProfilesScreen()),
            ),
            _Row(
              icon: Icons.description_outlined,
              label: 'Documents',
              onTap: () => go(const DocumentsScreen()),
            ),
            _Row(
              icon: Icons.swap_vert_rounded,
              label: 'Import / Export',
              onTap: () => go(const TransferScreen()),
            ),
            _Row(
              icon: Icons.cleaning_services_outlined,
              label: 'Clear share cache',
              onTap: () async {
                await StorageService.instance.clearExports();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Share cache cleared')),
                  );
                }
              },
            ),
          ]),
          const _GroupTitle('Security'),
          _Group(children: [
            SwitchListTile(
              secondary: const Icon(Icons.lock_outline_rounded),
              title: const Text('App Lock'),
              value: settings.appLockEnabled,
              onChanged: settings.setAppLockEnabled,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint_rounded),
              title: const Text('Biometric Lock'),
              value: settings.biometricEnabled,
              onChanged: settings.appLockEnabled
                  ? settings.setBiometricEnabled
                  : null,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.visibility_off_outlined),
              title: const Text('Mask numbers by default'),
              value: settings.maskByDefault,
              onChanged: settings.setMaskByDefault,
            ),
          ]),
          const _GroupTitle('Preferences'),
          _Group(children: [
            _Row(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () => go(const SettingsScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Theme'),
              trailing: DropdownButton<ThemeMode>(
                value: settings.themeMode,
                underline: const SizedBox.shrink(),
                onChanged: (m) => settings.setThemeMode(m ?? ThemeMode.system),
                items: const [
                  DropdownMenuItem(
                      value: ThemeMode.system, child: Text('System')),
                  DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                ],
              ),
            ),
          ]),
          const _GroupTitle('Support'),
          _Group(children: [
            _Row(
              icon: Icons.help_outline_rounded,
              label: 'Help & FAQ',
              onTap: () => _showHelp(context),
            ),
            _Row(
              icon: Icons.info_outline_rounded,
              label: 'About',
              onTap: () => go(const AboutScreen()),
            ),
          ]),
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                const AppLogo(size: 42),
                const SizedBox(height: 8),
                Text('Wallet · works fully offline',
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Help & FAQ',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            SizedBox(height: 14),
            _Faq('Where is my data stored?',
                'Everything stays in your phone\'s private app storage. There is no cloud, no account and no tracking.'),
            _Faq('How do reminders work?',
                'Documents with an expiry date alert you 30, 7 and 1 day before. Personal tasks alert you at the time you set.'),
            _Faq('How do I move to a new phone?',
                'Open More → Import / Export and transfer everything over Wi-Fi with a 6-digit code.'),
            _Faq('Can I hide sensitive numbers?',
                'Yes — masking hides all but the last digits when previewing or sharing a document.'),
          ],
        ),
      ),
    );
  }
}

class _Faq extends StatelessWidget {
  const _Faq(this.q, this.a);
  final String q;
  final String a;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(a,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )),
      );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(Divider(
            height: 1,
            indent: 56,
            color: scheme.outlineVariant.withValues(alpha: 0.4)));
      }
    }
    return Card(child: Column(children: rows));
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
}
