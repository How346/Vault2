import 'package:flutter/material.dart';

import '../widgets/brand.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [
          const Center(child: AppLogo(size: 96)),
          const SizedBox(height: 14),
          const Center(
            child: Text('Wallet',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text('Version 1.0.0',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 26),
          const Card(
            child: Column(
              children: [
                _Info(
                  icon: Icons.card_giftcard_rounded,
                  title: "What's New",
                  body:
                      'Bottom navigation, personal tasks & reminders, smarter document hub and a refreshed premium look.',
                ),
                _Info(
                  icon: Icons.shield_outlined,
                  title: 'Privacy Policy',
                  body:
                      'Wallet never uploads anything. All documents, images and reminders live only on this device.',
                ),
                _Info(
                  icon: Icons.article_outlined,
                  title: 'Terms of Use',
                  body:
                      'Provided as-is for personal document storage. You are responsible for keeping a backup of your device.',
                ),
                _Info(
                  icon: Icons.code_rounded,
                  title: 'Open Source Licenses',
                  body:
                      'Flutter, Hive, ML Kit, image, shelf, archive and other open-source packages.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('© 2026 Wallet. All rights reserved.',
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => ExpansionTile(
        leading: Icon(icon),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(body,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ],
      );
}
