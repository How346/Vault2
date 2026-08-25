import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../state/wallet_controller.dart';

const _profileColors = <int>[
  0xFF0F766E,
  0xFF1565C0,
  0xFFEF6C00,
  0xFF6A1B9A,
  0xFFAD1457,
  0xFF2E7D32,
  0xFF455A64,
];

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    final profiles = wallet.profiles;

    return Scaffold(
      appBar: AppBar(title: const Text('Profiles')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showProfileEditor(context),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add profile'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        itemCount: profiles.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final p = profiles[i];
          final active = p.id == wallet.activeProfileId;
          final count = wallet.documentCountForProfile(p.id);
          return Card(
            child: ListTile(
              leading: ProfileAvatar(profile: p),
              title: Text(p.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([
                if (p.relation.isNotEmpty) p.relation,
                count == 1 ? '1 document' : '$count documents',
              ].join(' • ')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (active)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.check_circle_rounded),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') {
                        showProfileEditor(context, existing: p);
                      } else if (v == 'delete') {
                        await _confirmDelete(context, p);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Rename')),
                      if (!p.isDefault)
                        const PopupMenuItem(
                            value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              onTap: () => wallet.setActiveProfile(p.id),
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Profile p) async {
    final wallet = context.read<WalletController>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${p.name}"?'),
        content: const Text(
            'Every document stored under this profile will be erased from this device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await wallet.deleteProfile(p);
  }
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.profile, this.size = 42});
  final Profile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Color(profile.colorValue);
    return Container(
      height: size,
      width: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: Text(
        profile.initials,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.38,
        ),
      ),
    );
  }
}

Future<void> showProfileEditor(BuildContext context, {Profile? existing}) async {
  final wallet = context.read<WalletController>();
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final relationCtrl = TextEditingController(text: existing?.relation ?? '');
  var color = existing?.colorValue ?? _profileColors.first;

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
      ),
      child: StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(existing == null ? 'New profile' : 'Edit profile',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: relationCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Relation', hintText: 'Spouse, Son, Father…'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              children: _profileColors.map((c) {
                final selected = c == color;
                return GestureDetector(
                  onTap: () => setLocal(() => color = c),
                  child: Container(
                    height: 34,
                    width: 34,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(
                              color: Theme.of(ctx).colorScheme.onSurface,
                              width: 2.5)
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );

  if (saved == true && nameCtrl.text.trim().isNotEmpty) {
    if (existing == null) {
      final p = await wallet.addProfile(
        name: nameCtrl.text.trim(),
        relation: relationCtrl.text.trim(),
        colorValue: color,
      );
      await wallet.setActiveProfile(p.id);
    } else {
      await wallet.updateProfile(
        existing,
        name: nameCtrl.text,
        relation: relationCtrl.text,
        colorValue: color,
      );
    }
  }
  nameCtrl.dispose();
  relationCtrl.dispose();
}
