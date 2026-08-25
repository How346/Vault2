import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/wallet_controller.dart';
import '../widgets/common.dart';
import 'document_view_screen.dart';

/// Flat list of every document of the active profile, with category filter
/// chips and sorting.
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final _searchCtrl = TextEditingController();
  String _categoryId = 'all';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    final scheme = Theme.of(context).colorScheme;
    final q = _searchCtrl.text.trim().toLowerCase();

    var docs = wallet.allDocuments;
    if (_categoryId != 'all') {
      docs = docs.where((d) => d.categoryId == _categoryId).toList();
    }
    if (q.isNotEmpty) {
      docs = docs
          .where((d) =>
              d.title.toLowerCase().contains(q) ||
              d.documentNumber.toLowerCase().contains(q))
          .toList();
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Documents'),
        actions: [
          PopupMenuButton<DocSort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.filter_list_rounded),
            onSelected: wallet.setSort,
            itemBuilder: (_) => const [
              PopupMenuItem(value: DocSort.recent, child: Text('Recently updated')),
              PopupMenuItem(value: DocSort.title, child: Text('Name (A–Z)')),
              PopupMenuItem(value: DocSort.expiry, child: Text('Expiry date')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 130),
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search documents',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
                    ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _chip('All', 'all', scheme),
                for (final c in wallet.categories) _chip(c.name, c.id, scheme),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (docs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 70),
              child: EmptyState(
                title: 'No documents yet',
                subtitle: 'Tap the scan button to add your first document.',
                icon: Icons.folder_open_rounded,
              ),
            )
          else
            ...List.generate(docs.length, (i) {
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
                        builder: (_) => DocumentViewScreen(docId: doc.id),
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _chip(String label, String id, ColorScheme scheme) {
    final selected = _categoryId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _categoryId = id),
      ),
    );
  }
}
