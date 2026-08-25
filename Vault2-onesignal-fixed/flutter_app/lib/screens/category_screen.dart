import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/wallet_controller.dart';
import '../widgets/common.dart';
import 'add_document_screen.dart';
import 'document_view_screen.dart';

class CategoryScreen extends StatelessWidget {
  const CategoryScreen({super.key, required this.categoryId});
  final String categoryId;

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    final category = wallet.category(categoryId);
    final docs = wallet.documentsIn(categoryId);

    return Scaffold(
      // 👇 फिक्स: बैक करते समय ब्लैक स्क्रीन रोकने के लिए बैकग्राउंड कलर सेट किया गया है
      backgroundColor: Theme.of(context).scaffoldBackgroundColor, 
      appBar: AppBar(title: Text(category?.name ?? 'Documents')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AddDocumentScreen(initialCategoryId: categoryId),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: docs.isEmpty
          ? const EmptyState(
              title: 'Nothing here yet',
              subtitle: 'Scan or pick a file to store it securely on this device.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final doc = docs[i];
                return AnimatedEntry(
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
                );
              },
            ),
    );
  }
}
