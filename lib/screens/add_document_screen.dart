import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/doc_item.dart';
import '../services/file_service.dart';
import '../services/notification_service.dart';
import '../services/ocr_service.dart';
import '../state/settings_controller.dart';
import '../state/wallet_controller.dart';
import '../utils/formatters.dart';
import 'scanner/camera_scan_screen.dart';

class AddDocumentScreen extends StatefulWidget {
  const AddDocumentScreen({
    super.key,
    this.initialCategoryId,
    this.existing,
  });

  final String? initialCategoryId;
  final DocItem? existing;

  @override
  State<AddDocumentScreen> createState() => _AddDocumentScreenState();
}

class _AddDocumentScreenState extends State<AddDocumentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  late String _categoryId;

  DateTime? _issueDate;
  DateTime? _expiryDate;

  bool _mask = true;
  bool _saving = false;
  bool _ocrBusy = false;

  final List<String> _pendingPaths = [];

  @override
  void initState() {
    super.initState();

    final doc = widget.existing;

    _categoryId =
        doc?.categoryId ?? widget.initialCategoryId ?? 'aadhaar';

    if (doc != null) {
      _titleCtrl.text = doc.title;
      _numberCtrl.text = doc.documentNumber;
      _notesCtrl.text = doc.notes;

      _issueDate = doc.issueDate;
      _expiryDate = doc.expiryDate;
      _mask = doc.maskByDefault;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (widget.existing == null) {
      _mask = context.read<SettingsController>().maskByDefault;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _numberCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({
    required bool issue,
  }) async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: (issue ? _issueDate : _expiryDate) ?? now,
      firstDate: DateTime(now.year - 60),
      lastDate: DateTime(now.year + 60),
    );

    if (picked == null || !mounted) return;

    setState(() {
      if (issue) {
        _issueDate = picked;
      } else {
        _expiryDate = picked;
      }
    });
  }

  Future<void> _addSource() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.document_scanner_outlined,
              ),
              title: const Text(
                'Smart scan (front & back)',
              ),
              subtitle: const Text(
                'Live edge guide, perspective crop, filters',
              ),
              onTap: () {
                Navigator.pop(ctx, 'smart');
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_camera_outlined,
              ),
              title: const Text(
                'Quick camera shot',
              ),
              onTap: () {
                Navigator.pop(ctx, 'camera');
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
              ),
              title: const Text(
                'Pick from gallery',
              ),
              onTap: () {
                Navigator.pop(ctx, 'gallery');
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.folder_open_outlined,
              ),
              title: const Text(
                'Pick PDF or image file',
              ),
              onTap: () {
                Navigator.pop(ctx, 'file');
              },
            ),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    final service = FileService.instance;

    List<String> added = [];

    try {
      switch (choice) {
        case 'smart':
          final pages = await Navigator.push<List<ScanPage>>(
            context,
            MaterialPageRoute(
              builder: (_) => const CameraScanScreen(),
            ),
          );

          if (!mounted) return;

          added = (pages ?? const <ScanPage>[])
              .map((e) => e.path)
              .toList();

          break;

        case 'camera':
          final path = await service.captureFromCamera();

          if (!mounted) return;

          if (path != null) {
            added = [path];
          }

          break;

        case 'gallery':
          added = await service.pickImages();

          if (!mounted) return;

          break;

        case 'file':
          added = await service.pickFiles();

          if (!mounted) return;

          break;
      }
    } on CaptureException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
        ),
      );

      return;
    } catch (_) {
      // Android can kill the app during capture.
      // Try to recover the lost capture.
      final recovered = await service.recoverLostCapture();

      if (!mounted) return;

      if (recovered != null) {
        added = [recovered];
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not attach that file.',
            ),
          ),
        );

        return;
      }
    }

    if (added.isEmpty || !mounted) return;

    setState(() {
      _pendingPaths.addAll(added);
    });

    await _offerAutofill(added);
  }

  Future<void> _offerAutofill(
    List<String> paths,
  ) async {
    final images = paths
        .where(
          (p) => !FileService.isPdf(p),
        )
        .toList();

    if (images.isEmpty || !mounted) return;

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Autofill fields?',
        ),
        content: const Text(
          'Read the text on the scan and fill the number, dates and title. '
          'Runs fully on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
            },
            child: const Text(
              'Not now',
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx, true);
            },
            child: const Text(
              'Autofill',
            ),
          ),
        ],
      ),
    );

    if (go != true || !mounted) return;

    setState(() {
      _ocrBusy = true;
    });

    OcrResult result;

    try {
      result = await OcrService.instance.extract(images);
    } catch (_) {
      result = const OcrResult();
    }

    if (!mounted) return;

    /*
     * IMPORTANT:
     * Read the Provider after the async operation and before
     * entering setState. This avoids the
     * use_build_context_synchronously analyzer warning.
     */
    final wallet = context.read<WalletController>();
    final catId = result.categoryId;

    setState(() {
      _ocrBusy = false;

      if (result.documentNumber != null &&
          _numberCtrl.text.trim().isEmpty) {
        _numberCtrl.text = result.documentNumber!;
      }

      if (result.title != null &&
          _titleCtrl.text.trim().isEmpty) {
        _titleCtrl.text = result.title!;
      }

      _issueDate ??= result.issueDate;
      _expiryDate ??= result.expiryDate;

      if (catId != null &&
          wallet.categories.any(
            (c) => c.id == catId,
          )) {
        _categoryId = catId;
      }
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.isEmpty
              ? 'Could not read enough text to autofill.'
              : 'Fields filled from the scan — please double-check.',
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final existingFiles =
        widget.existing?.filePaths ?? const <String>[];

    if (_pendingPaths.isEmpty && existingFiles.isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Attach at least one scan or file.',
          ),
        ),
      );

      return;
    }

    setState(() {
      _saving = true;
    });

    final wallet = context.read<WalletController>();

    final draft = widget.existing ??
        DocItem(
          id: wallet.newId(),
          title: '',
          categoryId: _categoryId,
          profileId: wallet.activeProfileId,
        );

    draft.title = _titleCtrl.text.trim();
    draft.categoryId = _categoryId;
    draft.documentNumber = _numberCtrl.text.trim();
    draft.notes = _notesCtrl.text.trim();
    draft.issueDate = _issueDate;
    draft.expiryDate = _expiryDate;
    draft.maskByDefault = _mask;

    try {
      await wallet.saveDocument(
        draft: draft,
        sourcePaths: _pendingPaths,
      );

      if (!mounted) return;

      await NotificationService.instance.requestPermissions();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Saving failed. Please try again.',
          ),
        ),
      );

      return;
    }

    if (!mounted) return;

    Navigator.pop(context);
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final wallet = context.watch<WalletController>();
    final scheme = Theme.of(context).colorScheme;

    final existingCount =
        widget.existing?.filePaths.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null
              ? 'Add document'
              : 'Edit document',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            16,
            8,
            16,
            32,
          ),
          children: [
            if (_ocrBusy)
              const Padding(
                padding: EdgeInsets.only(
                  bottom: 10,
                ),
                child: LinearProgressIndicator(
                  minHeight: 3,
                ),
              ),

            _AttachmentStrip(
              paths: _pendingPaths,
              existingCount: existingCount,
              onAdd: _addSource,
              onRemove: (i) {
                setState(() {
                  _pendingPaths.removeAt(i);
                });
              },
            ),

            const SizedBox(height: 18),

            TextFormField(
              controller: _titleCtrl,
              textCapitalization:
                  TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Title',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Give it a name';
                }

                return null;
              },
            ),

            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _categoryId,
              decoration: const InputDecoration(
                labelText: 'Category',
              ),
              items: wallet.categories
                  .map(
                    (c) => DropdownMenuItem<String>(
                      value: c.id,
                      child: Text(c.name),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _categoryId = v ?? _categoryId;
                });
              },
            ),

            const SizedBox(height: 12),

            TextFormField(
              controller: _numberCtrl,
              decoration: const InputDecoration(
                labelText: 'Document number',
                helperText:
                    'Stored locally; masked when shared',
              ),
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Issue date',
                    value: _issueDate,
                    onTap: () {
                      _pickDate(issue: true);
                    },
                    onClear: () {
                      setState(() {
                        _issueDate = null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateField(
                    label: 'Expiry date',
                    value: _expiryDate,
                    onTap: () {
                      _pickDate(issue: false);
                    },
                    onClear: () {
                      setState(() {
                        _expiryDate = null;
                      });
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes',
              ),
            ),

            const SizedBox(height: 8),

            SwitchListTile(
              value: _mask,
              onChanged: (v) {
                setState(() {
                  _mask = v;
                });
              },
              title: const Text(
                'Mask number by default',
              ),
              subtitle: const Text(
                'Hides all but the last 4 characters',
              ),
              contentPadding: EdgeInsets.zero,
            ),

            if (_expiryDate != null)
              Padding(
                padding: const EdgeInsets.only(
                  top: 4,
                  bottom: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.notifications_active_outlined,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Reminders will fire 30, 7 and 1 day before expiry.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.save_outlined,
                    ),
              label: Text(
                _saving
                    ? 'Saving…'
                    : 'Save to device',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(
    BuildContext context,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: value == null
              ? const Icon(
                  Icons.calendar_today_outlined,
                  size: 18,
                )
              : IconButton(
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                  ),
                  onPressed: onClear,
                ),
        ),
        child: Text(
          value == null
              ? 'Not set'
              : formatDate(value),
        ),
      ),
    );
  }
}

class _AttachmentStrip extends StatelessWidget {
  const _AttachmentStrip({
    required this.paths,
    required this.existingCount,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> paths;
  final int existingCount;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(
    BuildContext context,
  ) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 118,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 104,
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(18),
                border: Border.all(
                  color: scheme.outlineVariant,
                  width: 1.4,
                ),
              ),
              child: Column(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_a_photo_outlined,
                    color: scheme.primary,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add scan',
                    style: TextStyle(
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (existingCount > 0)
            Padding(
              padding: const EdgeInsets.only(
                left: 10,
              ),
              child: Container(
                width: 104,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      scheme.surfaceContainerHighest,
                  borderRadius:
                      BorderRadius.circular(18),
                ),
                child: Text(
                  '$existingCount saved',
                  style: const TextStyle(
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),

          ...List.generate(
            paths.length,
            (i) {
              final path = paths[i];
              final isPdf =
                  FileService.isPdf(path);

              return Padding(
                padding: const EdgeInsets.only(
                  left: 10,
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(18),
                      child: SizedBox(
                        width: 104,
                        height: 118,
                        child: isPdf
                            ? Container(
                                color: scheme
                                    .surfaceContainerHighest,
                                child: const Icon(
                                  Icons
                                      .picture_as_pdf_rounded,
                                ),
                              )
                            : Image.file(
                                File(path),
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                                isAntiAlias: false,
                                gaplessPlayback: true,
                              ),
                      ),
                    ),

                    Positioned(
                      top: 4,
                      right: 4,
                      child: InkWell(
                        onTap: () {
                          onRemove(i);
                        },
                        child: CircleAvatar(
                          radius: 13,
                          backgroundColor:
                              scheme.surface,
                          child: const Icon(
                            Icons.close,
                            size: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
