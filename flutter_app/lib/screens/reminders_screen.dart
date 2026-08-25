import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/task_item.dart';
import '../state/task_controller.dart';
import '../state/wallet_controller.dart';
import '../utils/formatters.dart';
import '../widgets/brand.dart';
import 'add_task_screen.dart';
import 'document_view_screen.dart';
import 'documents_screen.dart';
import 'tasks_screen.dart';

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    final tasks = context.watch<TaskController>();
    final scheme = Theme.of(context).colorScheme;

    final expiring = wallet.expiringSoon;
    final visibleTasks = tasks.all.take(5).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Icon(Icons.notifications_none_rounded, color: scheme.onSurface),
            const SizedBox(width: 10),
            const Text('Reminders'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Add reminder',
            icon: const Icon(Icons.add_circle, size: 28),
            color: scheme.primary,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddTaskScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 130),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: scheme.primary,
                  child: Icon(Icons.notifications_active_rounded,
                      size: 20, color: scheme.onPrimary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "We'll notify you on time, so you never miss what matters.",
                    style: TextStyle(
                        fontSize: 13.5, color: scheme.onSurface, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---------------------------------------------- document reminders
          _SectionCard(
            icon: Icons.description_rounded,
            title: 'DOCUMENT REMINDERS',
            subtitle: 'Important documents that need your attention',
            count: expiring.length,
            footerLabel: 'View all documents',
            onFooter: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DocumentsScreen()),
            ),
            children: expiring.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        'Nothing expiring soon. You are all set.',
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ]
                : [
                    for (var i = 0; i < expiring.length && i < 4; i++)
                      _ExpiryRow(
                        doc: expiring[i],
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                DocumentViewScreen(docId: expiring[i].id),
                          ),
                        ),
                      ),
                  ],
          ),
          const SizedBox(height: 16),

          // --------------------------------------------------- personal tasks
          _SectionCard(
            icon: Icons.checklist_rounded,
            title: 'MY TASKS & REMINDERS',
            subtitle: 'Your personal tasks and reminders',
            count: tasks.all.length,
            footerLabel: 'View all tasks',
            onFooter: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TasksScreen()),
            ),
            children: visibleTasks.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        'No tasks yet. Add your first reminder below.',
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ]
                : [
                    for (final t in visibleTasks) TaskRow(task: t),
                  ],
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddTaskScreen()),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Add reminder / task'),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.children,
    required this.footerLabel,
    required this.onFooter,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final List<Widget> children;
  final String footerLabel;
  final VoidCallback onFooter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: scheme.primary,
                          )),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Text('$count',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimaryContainer)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
            TextButton(
              onPressed: onFooter,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(footerLabel),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpiryRow extends StatelessWidget {
  const _ExpiryRow({required this.doc, required this.onTap});
  final dynamic doc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = daysUntil(doc.expiryDate) ?? 0;
    final color = days < 0
        ? scheme.error
        : days <= 30
            ? const Color(0xFFE0552B)
            : days <= 120
                ? const Color(0xFF7C4DFF)
                : scheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          children: [
            CategoryEmblem(
              categoryId: doc.categoryId as String,
              fallbackColor: 0xFF0F766E,
              size: 42,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.title as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14.5)),
                  const SizedBox(height: 2),
                  Text(
                    doc.expiryDate == null
                        ? 'No expiry'
                        : 'Expires on ${formatDate(doc.expiryDate as DateTime)}',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(days < 0 ? 'Expired' : '$days',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: color)),
                Text(days < 0 ? '${-days} days ago' : 'days left',
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// A single task row with a check toggle and overflow menu.
class TaskRow extends StatelessWidget {
  const TaskRow({super.key, required this.task});
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ctrl = context.read<TaskController>();
    final chip = taskChipLabel(task);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          InkResponse(
            onTap: () => ctrl.toggleDone(task),
            radius: 22,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                task.completed
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 24,
                color: task.completed
                    ? scheme.primary
                    : (task.repeat == TaskRepeat.once
                        ? scheme.outline
                        : scheme.tertiary),
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (task.imagePath != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(task.imagePath!),
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(width: 36, height: 36),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    decoration:
                        task.completed ? TextDecoration.lineThrough : null,
                    color: task.completed ? scheme.onSurfaceVariant : null,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.calendar_today_rounded,
                        size: 12, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(taskDateLabel(task),
                        style: TextStyle(
                            fontSize: 11.5, color: scheme.onSurfaceVariant)),
                    if (task.hasTime) ...[
                      const SizedBox(width: 10),
                      Icon(Icons.schedule_rounded,
                          size: 12, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(taskTimeLabel(task),
                          style: TextStyle(
                              fontSize: 11.5, color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: chip.$2.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(chip.$1,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: chip.$2)),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 18),
            onSelected: (v) async {
              if (v == 'edit') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AddTaskScreen(task: task)),
                );
              } else if (v == 'delete') {
                await ctrl.delete(task);
              } else {
                await ctrl.toggleDone(task);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'done',
                  child: Text(task.completed
                      ? 'Mark as pending'
                      : 'Mark as completed')),
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

(String, Color) taskChipLabel(TaskItem task) {
  if (task.completed) return ('Completed', const Color(0xFF6B7280));
  if (task.repeat != TaskRepeat.once) {
    return (
      task.repeat.label,
      task.repeat == TaskRepeat.daily
          ? const Color(0xFFEA8C00)
          : const Color(0xFFE0552B)
    );
  }
  final d = daysUntil(task.dueAt) ?? 0;
  if (d < 0) return ('Overdue', const Color(0xFFD32F2F));
  if (d == 0) return ('Today', const Color(0xFF7C4DFF));
  if (d == 1) return ('Tomorrow', const Color(0xFF2A76D2));
  return ('In $d days', const Color(0xFF0F766E));
}

String taskDateLabel(TaskItem task) {
  if (task.repeat == TaskRepeat.daily) return 'Daily';
  if (task.repeat == TaskRepeat.weekly) return 'Weekly';
  if (task.repeat == TaskRepeat.monthly) return 'Monthly';
  final d = daysUntil(task.dueAt);
  if (d == 0) return 'Today';
  if (d == 1) return 'Tomorrow';
  return formatDate(task.dueAt);
}

String taskTimeLabel(TaskItem task) {
  final h = task.dueAt.hour;
  final m = task.dueAt.minute.toString().padLeft(2, '0');
  final suffix = h >= 12 ? 'PM' : 'AM';
  final hour12 = h % 12 == 0 ? 12 : h % 12;
  return '$hour12:$m $suffix';
}
