import 'package:hive/hive.dart';

enum TaskRepeat { once, daily, weekly, monthly }

enum TaskPriority { low, medium, high }

extension TaskRepeatLabel on TaskRepeat {
  String get label => switch (this) {
        TaskRepeat.once => 'Once',
        TaskRepeat.daily => 'Daily',
        TaskRepeat.weekly => 'Weekly',
        TaskRepeat.monthly => 'Monthly',
      };
}

extension TaskPriorityLabel on TaskPriority {
  String get label => switch (this) {
        TaskPriority.low => 'Low',
        TaskPriority.medium => 'Medium',
        TaskPriority.high => 'High',
      };
}

/// typeId 4 — a personal task / reminder. 100% local.
class TaskItem extends HiveObject {
  final String id;
  String title;
  String notes;
  DateTime dueAt;
  bool hasTime;
  TaskRepeat repeat;
  TaskPriority priority;
  bool notify;
  bool completed;
  String profileId;
  DateTime createdAt;
  String? imagePath;

  TaskItem({
    required this.id,
    required this.title,
    this.notes = '',
    required this.dueAt,
    this.hasTime = true,
    this.repeat = TaskRepeat.once,
    this.priority = TaskPriority.medium,
    this.notify = true,
    this.completed = false,
    this.profileId = 'me',
    DateTime? createdAt,
    this.imagePath,
  }) : createdAt = createdAt ?? DateTime.now();

  int _hashWith(int salt) {
    var hash = 2166136261;
    for (final codeUnit in id.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return (hash ^ salt) & 0x7fffffff;
  }

  /// Id used for the ordinary "it's time" alert.
  int get notificationId => _hashWith(0x5f3a);

  /// Id used for the ongoing "you're late" chronometer notification. Kept
  /// distinct from [notificationId] so the two never collide or overwrite
  /// each other.
  int get lateNotificationId => _hashWith(0x1a7e10);
}

class TaskItemAdapter extends TypeAdapter<TaskItem> {
  @override
  final int typeId = 4;

  @override
  TaskItem read(BinaryReader reader) {
    final m = reader.readMap().cast<String, dynamic>();
    return TaskItem(
      id: m['id'] as String,
      title: m['title'] as String? ?? 'Task',
      notes: m['notes'] as String? ?? '',
      dueAt: DateTime.fromMillisecondsSinceEpoch(
          (m['dueAt'] as int?) ?? DateTime.now().millisecondsSinceEpoch),
      hasTime: m['hasTime'] as bool? ?? true,
      repeat: TaskRepeat.values[(m['repeat'] as int?) ?? 0],
      priority: TaskPriority.values[(m['priority'] as int?) ?? 1],
      notify: m['notify'] as bool? ?? true,
      completed: m['completed'] as bool? ?? false,
      profileId: m['profileId'] as String? ?? 'me',
      createdAt: m['createdAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
      imagePath: m['imagePath'] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, TaskItem o) {
    writer.writeMap(<String, dynamic>{
      'id': o.id,
      'title': o.title,
      'notes': o.notes,
      'dueAt': o.dueAt.millisecondsSinceEpoch,
      'hasTime': o.hasTime,
      'repeat': o.repeat.index,
      'priority': o.priority.index,
      'notify': o.notify,
      'completed': o.completed,
      'profileId': o.profileId,
      'createdAt': o.createdAt.millisecondsSinceEpoch,
      'imagePath': o.imagePath,
    });
  }
}
