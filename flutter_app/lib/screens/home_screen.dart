import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/doc_category.dart';
import '../state/wallet_controller.dart';
import '../utils/formatters.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import 'category_screen.dart';
import 'document_view_screen.dart';
import 'profiles_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _addCategoryDialog() async {
    final nameCtrl = TextEditingController();
    final wallet = context.read<WalletController>();

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New category'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Property papers',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (created == true && nameCtrl.text.trim().isNotEmpty) {
      await wallet.addCategory(
        name: nameCtrl.text.trim(),
        iconCodePoint: Icons.folder_rounded.codePoint,
        colorValue: 0xFF00695C,
      );
    }

    nameCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    final scheme = Theme.of(context).colorScheme;
    final searching = wallet.query.trim().isNotEmpty;
    final expiring = wallet.expiringSoon;
    final name = wallet.activeProfile?.name ?? 'there';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 130),
          children: [
            // ------------------------------------------------------- header
            Row(
              children: [
                const AppLogo(size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hi,',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Container(
                            width: 20,
                            height: 2.5,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [scheme.primary, scheme.secondary],
                              ),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              'Your private wallet, ready when you are.',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.02,
                                color: scheme.onSurfaceVariant.withValues(alpha: 0.82),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _RoundAction(
                  icon: Icons.person_outline_rounded,
                  tooltip: 'Profiles',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProfilesScreen(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _RoundAction(
                  icon: Icons.settings_outlined,
                  tooltip: 'Settings',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SettingsScreen(),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ------------------------------------------------------- search
            TextField(
              controller: _searchCtrl,
              onChanged: wallet.search,
              decoration: InputDecoration(
                hintText: 'Search documents',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searching
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchCtrl.clear();
                          wallet.search('');
                        },
                      )
                    : PopupMenuButton<DocSort>(
                        tooltip: 'Sort',
                        icon: const Icon(Icons.tune_rounded),
                        onSelected: wallet.setSort,
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: DocSort.recent,
                            child: Text('Recently updated'),
                          ),
                          PopupMenuItem(
                            value: DocSort.title,
                            child: Text('Name (A–Z)'),
                          ),
                          PopupMenuItem(
                            value: DocSort.expiry,
                            child: Text('Expiry date'),
                          ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 14),

            if (searching)
              ..._searchResults(wallet)
            else
              ..._hub(wallet, expiring, scheme, name),
          ],
        ),
      ),
    );
  }

  List<Widget> _searchResults(WalletController wallet) {
    final docs = wallet.allDocuments;

    if (docs.isEmpty) {
      return const [
        SizedBox(height: 80),
        EmptyState(
          title: 'No matches',
          subtitle: 'Try a different name or document number.',
          icon: Icons.search_off_rounded,
        ),
      ];
    }

    return List.generate(
      docs.length,
      (i) {
        final doc = docs[i];

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AnimatedEntry(
            index: i,
            child: DocumentTile(
              doc: doc,
              masked: doc.maskByDefault,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DocumentViewScreen(
                    docId: doc.id,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _hub(
    WalletController wallet,
    List expiring,
    ColorScheme scheme,
    String name,
  ) {
    final total = wallet.allDocuments.length;

    return [
      // ------------------------------------------------------ offline banner
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: scheme.surface,
              child: Icon(
                Icons.lock_rounded,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    total == 1
                        ? '1 document stored offline'
                        : '$total documents stored offline',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'No cloud, no accounts, no tracking.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.verified_rounded,
              size: 30,
              color: scheme.primary.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),

      // ------------------------------------------------------ expiring soon
      if (expiring.isNotEmpty) ...[
        const SizedBox(height: 22),
        const _SectionTitle('Expiring soon'),
        const SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: expiring.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final doc = expiring[i];
              final days = daysUntil(doc.expiryDate) ?? 0;

              return AnimatedEntry(
                index: i,
                child: SizedBox(
                  width: 220,
                  child: Card(
                    color: days < 0
                        ? scheme.errorContainer
                        : scheme.tertiaryContainer,
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DocumentViewScreen(
                            docId: doc.id,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              doc.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              expiryLabel(doc.expiryDate),
                              style: const TextStyle(
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],

      // ------------------------------------------------------ pinned
      if (wallet.favorites.isNotEmpty) ...[
        const SizedBox(height: 22),
        const _SectionTitle('Pinned'),
        const SizedBox(height: 10),
        ...List.generate(
          wallet.favorites.length,
          (i) {
            final doc = wallet.favorites[i];

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AnimatedEntry(
                index: i,
                child: DocumentTile(
                  doc: doc,
                  masked: doc.maskByDefault,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DocumentViewScreen(
                        docId: doc.id,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],

      // ------------------------------------------------------ categories
      const SizedBox(height: 22),

      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const _SectionTitle('Categories'),
          TextButton.icon(
            onPressed: _addCategoryDialog,
            icon: const Icon(
              Icons.add,
              size: 18,
            ),
            label: const Text('New category'),
          ),
        ],
      ),

      const SizedBox(height: 6),

      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: wallet.categories.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.15,
        ),
        itemBuilder: (_, i) {
          final DocCategory cat = wallet.categories[i];

          return AnimatedEntry(
            index: i,
            child: CategoryCard(
              category: cat,
              count: wallet.countIn(cat.id),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CategoryScreen(
                    categoryId: cat.id,
                  ),
                ),
              ),
              onLongPress: cat.isBuiltIn
                  ? null
                  : () => _confirmDeleteCategory(cat),
            ),
          );
        },
      ),
    ];
  }

  Future<void> _confirmDeleteCategory(DocCategory cat) async {
    final wallet = context.read<WalletController>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${cat.name}"?'),
        content: const Text(
          'Documents inside will move to "Others".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await wallet.deleteCategory(cat);
    }
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              icon,
              size: 21,
              color: scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
    );
  }
}
