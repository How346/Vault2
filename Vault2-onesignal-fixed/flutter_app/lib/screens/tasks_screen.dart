import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/task_item.dart';
import '../state/task_controller.dart';
import '../utils/formatters.dart';
import 'add_task_screen.dart';
import 'reminders_screen.dart';

/// Full task list with All / Pending / Completed filters.
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<TaskController>();
    final scheme = Theme.of(context).colorScheme;
    final tasks = ctrl.filtered;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('My Tasks & Reminders')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<TaskFilter>(
              segments: const [
                ButtonSegment(value: TaskFilter.all, label: Text('All')),
                ButtonSegment(value: TaskFilter.pending, label: Text('Pending')),
                ButtonSegment(
                    value: TaskFilter.completed, label: Text('Completed')),
              ],
              selected: {ctrl.filter},
              showSelectedIcon: false,
              onSelectionChanged: (s) => ctrl.setFilter(s.first),
            ),
          ),
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Text(
                      'Nothing here yet.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                    itemCount: tasks.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    itemBuilder: (_, i) => TaskRow(task: tasks[i]),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'task-fab',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddTaskScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add reminder / task'),
      ),
    );
  }
}

/// Small helper reused by the reminders hub.
String humanDue(TaskItem t) => formatDate(t.dueAt);
