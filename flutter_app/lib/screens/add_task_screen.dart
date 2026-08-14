import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/doc_item.dart';
import '../models/task_item.dart';
import '../state/task_controller.dart';
import '../state/wallet_controller.dart';
import '../utils/formatters.dart';
import 'document_view_screen.dart';

/// Create or edit a task, or attach a reminder to an existing document.
class AddTaskScreen extends StatefulWidget {
  const AddTaskScreen({super.key, this.task});
  final TaskItem? task;

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  late final TextEditingController _title =
      TextEditingController(text: widget.task?.title ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.task?.notes ?? '');

  int _tab = 0; // 0 = task, 1 = document reminder
  late DateTime _date = widget.task?.dueAt ?? DateTime.now();
  late TimeOfDay _time = TimeOfDay(
    hour: widget.task?.dueAt.hour ?? 10,
    minute: widget.task?.dueAt.minute ?? 0,
  );
  late TaskRepeat _repeat = widget.task?.repeat ?? TaskRepeat.once;
  late TaskPriority _priority = widget.task?.priority ?? TaskPriority.medium;
  late bool _notify = widget.task?.notify ?? true;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 25),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Add a title first')));
      return;
    }

    final due = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    final ctrl = context.read<TaskController>();
    final existing = widget.task;

    try {
      if (existing == null) {
        await ctrl.create(
          title: title,
          notes: _notes.text.trim(),
          dueAt: due,
          repeat: _repeat,
          priority: _priority,
          notify: _notify,
          profileId: context.read<WalletController>().activeProfileId,
        );
      } else {
        existing
          ..title = title
          ..notes = _notes.text.trim()
          ..dueAt = due
          ..repeat = _repeat
          ..priority = _priority
          ..notify = _notify;
        await ctrl.save(existing, isNew: false);
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      final exactMissing = error is StateError &&
          error.message.toString().contains('Precise reminder access');
      if (exactMissing) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enable “Alarms & reminders” for Wallet, then return here. Your reminder is saved.'),
            duration: Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reminder saved, but scheduling failed: $error'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.task == null ? 'Add Reminder / Task' : 'Edit task'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          if (widget.task == null)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  _tabButton('Task', 0, scheme),
                  _tabButton('Document Reminder', 1, scheme),
                ],
              ),
            ),
          const SizedBox(height: 14),
          if (_tab == 1 && widget.task == null)
            const _DocumentReminderPanel()
          else ...[
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Task title',
                prefixIcon: Icon(Icons.description_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 4,
              decoration: const InputDecoration(
                  hintText: 'Description (optional)'),
            ),
            const SizedBox(height: 14),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.calendar_month_rounded),
                    title: const Text('Date'),
                    trailing: Text(formatDate(_date),
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                    onTap: _pickDate,
                  ),
                  Divider(
                      height: 1,
                      color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  ListTile(
                    leading: const Icon(Icons.schedule_rounded),
                    title: const Text('Time'),
                    trailing: Text(_time.format(context),
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                    onTap: _pickTime,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.repeat_rounded),
                    title: const Text('Repeat'),
                    trailing: DropdownButton<TaskRepeat>(
                      value: _repeat,
                      underline: const SizedBox.shrink(),
                      onChanged: (v) =>
                          setState(() => _repeat = v ?? TaskRepeat.once),
                      items: [
                        for (final r in TaskRepeat.values)
                          DropdownMenuItem(value: r, child: Text(r.label)),
                      ],
                    ),
                  ),
                  Divider(
                      height: 1,
                      color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: const Text('Priority'),
                    trailing: DropdownButton<TaskPriority>(
                      value: _priority,
                      underline: const SizedBox.shrink(),
                      onChanged: (v) =>
                          setState(() => _priority = v ?? TaskPriority.medium),
                      items: [
                        for (final p in TaskPriority.values)
                          DropdownMenuItem(value: p, child: Text(p.label)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: SwitchListTile(
                value: _notify,
                onChanged: (v) => setState(() => _notify = v),
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('Enable notification'),
                subtitle: const Text('You will receive an alert on time'),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(widget.task == null ? 'Add reminder / task' : 'Save changes'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tabButton(String label, int index, ColorScheme scheme) {
    final selected = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? scheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 1.4,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Lists documents with an expiry so the user can jump straight to one and
/// review its automatic reminders.
class _DocumentReminderPanel extends StatelessWidget {
  const _DocumentReminderPanel();

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    final scheme = Theme.of(context).colorScheme;
    final docs = wallet.allDocuments
        .where((d) => d.expiryDate != null)
        .toList()
      ..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));

    if (docs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Center(
          child: Text(
            'No documents with an expiry date yet.\nAdd an expiry to a document to get alerts.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final DocItem d in docs)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const Icon(Icons.event_available_rounded),
              title: Text(d.title),
              subtitle: Text(
                  'Alerts at 30, 7 and 1 day before ${formatDate(d.expiryDate)}'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => DocumentViewScreen(docId: d.id)),
              ),
            ),
          ),
      ],
    );
  }
}
