import 'dart:math';

import 'package:flutter/material.dart';

import '../models/task_item.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';

enum TaskFilter { all, pending, completed }

class TaskController extends ChangeNotifier {
  final _box = StorageService.instance.tasks;

  TaskFilter _filter = TaskFilter.all;
  TaskFilter get filter => _filter;

  void setFilter(TaskFilter value) {
    _filter = value;
    notifyListeners();
  }

  void refresh() => notifyListeners();

  List<TaskItem> get all {
    final list = _box.values.toList()
      ..sort((a, b) {
        if (a.completed != b.completed) return a.completed ? 1 : -1;
        return a.dueAt.compareTo(b.dueAt);
      });
    return list;
  }

  List<TaskItem> get pending => all.where((t) => !t.completed).toList();
  List<TaskItem> get completed => all.where((t) => t.completed).toList();

  List<TaskItem> get filtered => switch (_filter) {
        TaskFilter.all => all,
        TaskFilter.pending => pending,
        TaskFilter.completed => completed,
      };

  int get pendingCount => pending.length;

  String _newId() =>
      '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(99999)}';

  Future<TaskItem> save(TaskItem draft, {bool isNew = true}) async {
    await _box.put(draft.id, draft);
    await _sync(draft);
    notifyListeners();
    return draft;
  }

  Future<TaskItem> create({
    required String title,
    String notes = '',
    required DateTime dueAt,
    bool hasTime = true,
    TaskRepeat repeat = TaskRepeat.once,
    TaskPriority priority = TaskPriority.medium,
    bool notify = true,
    String profileId = 'me',
  }) async {
    final task = TaskItem(
      id: 't-${_newId()}',
      title: title,
      notes: notes,
      dueAt: dueAt,
      hasTime: hasTime,
      repeat: repeat,
      priority: priority,
      notify: notify,
      profileId: profileId,
    );
    return save(task);
  }

  Future<void> toggleDone(TaskItem task) async {
    task.completed = !task.completed;
    await task.save();
    await _sync(task);
    notifyListeners();
  }

  Future<void> delete(TaskItem task) async {
    try {
      await NotificationService.instance.cancelTask(task);
    } catch (_) {}
    await _box.delete(task.id);
    notifyListeners();
  }

  Future<void> _sync(TaskItem task) async {
    try {
      if (task.completed || !task.notify) {
        await NotificationService.instance.cancelTask(task);
        return;
      }

      await NotificationService.instance.requestPermissions(
        requestExactAlarm: true,
      );
      await NotificationService.instance.scheduleTask(task);
    } catch (_) {
      // Keep the task saved even if Android temporarily rejects an alarm.
      // Startup/next edit will retry scheduling.
    }
  }
}
