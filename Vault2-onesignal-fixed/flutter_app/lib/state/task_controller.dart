import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/task_item.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';

enum TaskFilter { all, pending, completed }

class TaskController extends ChangeNotifier {
  final _box = StorageService.instance.tasks;
  StreamSubscription<BoxEvent>? _boxSub;

  TaskController() {
    // The STOP action on the overdue notification can complete a task by
    // writing to this box directly (it may run in a background isolate
    // with no TaskController around to call notifyListeners()). Watching
    // the box means the UI stays in sync no matter where the write came
    // from.
    _boxSub = _box.watch().listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _boxSub?.cancel();
    super.dispose();
  }

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

  /// Generates an id up front, so callers that need to import a file (e.g.
  /// an attached image) can copy it into storage under this exact id before
  /// the task is persisted.
  String newId() => 't-${_newId()}';

  Future<TaskItem> create({
    required String title,
    String notes = '',
    required DateTime dueAt,
    bool hasTime = true,
    TaskRepeat repeat = TaskRepeat.once,
    TaskPriority priority = TaskPriority.medium,
    bool notify = true,
    String profileId = 'me',
    String? id,
    String? imagePath,
  }) async {
    final task = TaskItem(
      id: id ?? newId(),
      title: title,
      notes: notes,
      dueAt: dueAt,
      hasTime: hasTime,
      repeat: repeat,
      priority: priority,
      notify: notify,
      profileId: profileId,
      imagePath: imagePath,
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
    if (task.imagePath != null) {
      try {
        await StorageService.instance.deleteFilesFor(task.id);
      } catch (_) {}
    }
    await _box.delete(task.id);
    notifyListeners();
  }

  Future<void> _sync(TaskItem task) async {
    try {
      if (task.completed || !task.notify) {
        await NotificationService.instance.cancelTask(task);
        return;
      }

      final ready = await NotificationService.instance.ensureReminderAccess();
      if (!ready) {
        throw StateError(
          'Precise reminder access is required. Enable Alarms & reminders for Wallet, then return to the app.',
        );
      }
      await NotificationService.instance.scheduleTask(task);
    } catch (error) {
      // Keep the task saved. The UI can tell the user why scheduling did not
      // complete and Android Settings can be opened immediately.
      rethrow;
    }
  }
}
