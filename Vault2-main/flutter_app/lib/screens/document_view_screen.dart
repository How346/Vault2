import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../services/share_service.dart';
import '../state/wallet_controller.dart';
import '../utils/formatters.dart';
import '../utils/masking.dart';
import '../widgets/flip_card.dart';
import 'add_document_screen.dart';

class DocumentViewScreen extends StatefulWidget {
  const DocumentViewScreen({super.key, required this.docId});
  final String docId;

  @override
  State<DocumentViewScreen> createState() => _DocumentViewScreenState();
}

class _DocumentViewScreenState extends State<DocumentViewScreen> {
  bool? _maskedOverride;
  final _flipKey = GlobalKey<FlipCardViewState>();

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    final doc = wallet.docById(widget.docId);

    if (doc == null) {
      return const Scaffold(body: Center(child: Text('Document removed')));
    }

    final masked = _maskedOverride ?? doc.maskByDefault;
    final scheme = Theme.of(context).colorScheme;
    final number = doc.documentNumber.isEmpty
        ? '—'
        : (masked
            ? Masking.forCategory(doc.categoryId, doc.documentNumber)
            : doc.documentNumber);

    return Scaffold(
      appBar: AppBar(
        title: Text(doc.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: doc.favorite ? 'Unpin' : 'Pin',
            icon: Icon(doc.favorite ? Icons.star_rounded : Icons.star_border_rounded),
            onPressed: () => wallet.toggleFavorite(doc),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AddDocumentScreen(existing: doc)),
                );
              } else if (v == 'delete') {
                await _confirmDelete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _maskedOverride = !masked),
                  icon: Icon(masked ? Icons.visibility_off : Icons.visibility),
                  label: Text(masked ? 'Masked' : 'Unmasked'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _shareSheet(masked),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (!doc.isPdf && doc.filePaths.length >= 2) ...[
            FlipCardView(
              key: _flipKey,
              frontPath: doc.filePaths[0],
              backPath: doc.filePaths[1],
            ),
            const SizedBox(height: 10),
            Center(
              child: OutlinedButton.icon(
                onPressed: () => _flipKey.currentState?.flip(),
                icon: const Icon(Icons.flip_camera_android_rounded),
                label: const Text('Flip card'),
              ),
            ),
            if (doc.filePaths.length > 2) ...[
              const SizedBox(height: 12),
              _Preview(paths: doc.filePaths.sublist(2), isPdf: false),
            ],
          ] else
            _Preview(paths: doc.filePaths, isPdf: doc.isPdf),
          const SizedBox(height: 18),
          Card(
            child: Column(
              children: [
                _Row(
                  label: 'Document number',
                  value: number,
                  trailing: doc.documentNumber.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Copy',
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(
                                text: masked ? number : doc.documentNumber));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Copied')),
                            );
                          },
                        ),
                ),
                _Row(label: 'Issued on', value: formatDate(doc.issueDate)),
                _Row(label: 'Expires on', value: expiryLabel(doc.expiryDate)),
                _Row(
                  label: 'Category',
                  value: wallet.category(doc.categoryId)?.name ?? '—',
                ),
                if (doc.notes.trim().isNotEmpty)
                  _Row(label: 'Notes', value: doc.notes.trim()),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.lock_outline, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Stored only on this device. Sharing uses your phone\'s share sheet.',
                  style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _shareSheet(bool masked) async {
    final doc = context.read<WalletController>().docById(widget.docId);
    if (doc == null) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Share masked copy'),
              subtitle: const Text('Sensitive digits hidden'),
              onTap: () => Navigator.pop(ctx, 'masked'),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('Share original'),
              onTap: () => Navigator.pop(ctx, 'original'),
            ),
            ListTile(
              leading: const Icon(Icons.short_text),
              title: const Text('Share details only'),
              onTap: () => Navigator.pop(ctx, 'details'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    if (choice == 'details') {
      await ShareService.instance.shareDetailsOnly(doc, masked: masked);
    } else {
      await ShareService.instance
          .shareDocument(doc, masked: choice == 'masked');
    }
  }

  Future<void> _confirmDelete() async {
    final wallet = context.read<WalletController>();
    final doc = wallet.docById(widget.docId);
    if (doc == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete document?'),
        content: const Text('The files will be erased from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await wallet.deleteDocument(doc);
      if (mounted) Navigator.pop(context);
    }
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.paths, required this.isPdf});
  final List<String> paths;
  final bool isPdf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (paths.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 320,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.92),
        itemCount: paths.length,
        itemBuilder: (_, i) {
          final path = paths[i];
          final exists = File(path).existsSync();
          final pdf = path.toLowerCase().endsWith('.pdf');
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Card(
              child: InkWell(
                onTap: exists ? () => OpenFilex.open(path) : null,
                child: (!exists)
                    ? const Center(child: Text('File missing'))
                    : pdf
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.picture_as_pdf_rounded,
                                    size: 52, color: scheme.primary),
                                const SizedBox(height: 10),
                                const Text('Tap to open PDF'),
                              ],
                            ),
                          )
                        : InteractiveViewer(
                            maxScale: 4,
                            child: Image.file(File(path), fit: BoxFit.contain),
                          ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.trailing});
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
