import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/doc_item.dart';
import '../models/task_item.dart';
import 'storage_service.dart';

/// Reliable, offline local notifications.
///
/// Reminder notifications are deliberately scheduled with
/// exactAllowWhileIdle. We do NOT silently fall back to inexact alarms: if
/// Android has not granted exact-alarm access, the user is told to enable it.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  bool _initializing = false;
  String _timezoneName = 'UTC';

  static const AndroidNotificationChannel _expiryChannel =
      AndroidNotificationChannel(
    'expiry_reminders_v3',
    'Document expiry reminders',
    description: 'Local alerts before a document expires',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel _taskChannel =
      AndroidNotificationChannel(
    'task_reminders_v3',
    'Tasks & reminders',
    description: 'Local alerts for personal tasks',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel _testChannel =
      AndroidNotificationChannel(
    'wallet_test_v3',
    'Wallet test notifications',
    description: 'Immediate notification used to verify notification delivery',
    importance: Importance.max,
  );

  Future<void> init() async {
    if (_ready) return;
    if (_initializing) {
      while (_initializing) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return;
    }

    _initializing = true;
    try {
      tzdata.initializeTimeZones();

      try {
        final zone = await FlutterTimezone.getLocalTimezone();
        _timezoneName = zone.identifier;
        tz.setLocalLocation(tz.getLocation(zone.identifier));
      } catch (error) {
        debugPrint('Could not read device timezone: $error');
        tz.setLocalLocation(tz.UTC);
        _timezoneName = 'UTC';
      }

      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@drawable/notification_icon'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );

      await _plugin.initialize(settings);

      final android = _android;
      await android?.createNotificationChannel(_expiryChannel);
      await android?.createNotificationChannel(_taskChannel);
      await android?.createNotificationChannel(_testChannel);

      _ready = true;
    } finally {
      _initializing = false;
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  String get timezoneName => _timezoneName;

  Future<bool> notificationsEnabled() async {
    await init();
    return await _android?.areNotificationsEnabled() ?? true;
  }

  Future<bool> exactAlarmPermissionGranted() async {
    await init();
    try {
      return await _android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Requests notification permission and, when requested by an explicit
  /// user action, opens Android's Exact Alarm access page.
  ///
  /// We intentionally use SCHEDULE_EXACT_ALARM rather than declaring both
  /// exact-alarm permissions. Android recommends choosing one; SCHEDULE is
  /// the appropriate user-granted permission for a secondary reminder
  /// feature. See Android's exact-alarm documentation.
  Future<bool> requestPermissions({bool requestExactAlarm = false}) async {
    await init();

    await _android?.requestNotificationsPermission();

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);

    if (requestExactAlarm) {
      await _requestExactAlarmAccess();
    }

    return await notificationsEnabled();
  }

  Future<bool> _requestExactAlarmAccess() async {
    final android = _android;
    if (android == null) return true;

    try {
      if (await android.canScheduleExactNotifications() == true) return true;
      await android.requestExactAlarmsPermission();
      // The Android Settings activity is asynchronous. Re-check immediately;
      // the lifecycle callback in main.dart will retry when the user returns.
      return (await android.canScheduleExactNotifications()) == true;
    } catch (error) {
      debugPrint('Exact alarm permission request failed: $error');
      return false;
    }
  }

  Future<bool> showTestNotification() async {
    await init();
    final enabled = await requestPermissions();
    if (!enabled) return false;

    await _plugin.show(
      987654,
      'Wallet',
      'Test notification — notifications are working.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'wallet_test_v3',
          'Wallet test notifications',
          channelDescription:
              'Immediate notification used to verify notification delivery',
          icon: 'notification_icon',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          autoCancel: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: 'notification_test',
    );
    return true;
  }

  Future<void> rescheduleStoredNotifications() async {
    await init();
    if (!await notificationsEnabled()) return;
    if (!await exactAlarmPermissionGranted()) return;

    final storage = StorageService.instance;
    for (final doc in storage.documents.values) {
      try {
        final ids = await scheduleExpiry(doc);
        doc.reminderIds = ids;
        await doc.save();
      } catch (error) {
        debugPrint('Document reminder restore failed: $error');
      }
    }

    for (final task in storage.tasks.values) {
      try {
        await scheduleTask(task);
      } catch (error) {
        debugPrint('Task reminder restore failed: $error');
      }
    }
  }

  /// Called after returning from Android Settings. If exact-alarm access was
  /// just granted, rebuild all future schedules immediately.
  Future<void> onAppResumed() async {
    try {
      if (!await exactAlarmPermissionGranted()) return;
      await rescheduleStoredNotifications();
    } catch (error) {
      debugPrint('Reminder resume sync failed: $error');
    }
  }

  Future<void> _requireExactAlarm() async {
    if (!await notificationsEnabled()) {
      throw StateError('Wallet notifications are disabled.');
    }
    if (!await exactAlarmPermissionGranted()) {
      throw StateError(
        'Exact Alarm access is disabled. Open Wallet → Settings → Reminders and enable precise reminders.',
      );
    }
  }

  tz.TZDateTime _localDateTime(DateTime value) {
    // DateTime values created by the date/time pickers represent the user's
    // local wall-clock time. Reconstruct it in tz.local so DST is handled by
    // the timezone package rather than by a raw millisecond conversion.
    return tz.TZDateTime(
      tz.local,
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
    );
  }

  Future<void> scheduleAllForDocument(DocItem doc) async {
    await init();

    final expiry = doc.expiryDate;
    if (expiry == null) {
      await cancelFor(doc);
      doc.reminderIds = <int>[];
      return;
    }

    await _requireExactAlarm();
    await cancelFor(doc);

    final ids = <int>[];
    for (final offset in const [30, 7, 1]) {
      final when = DateTime(
        expiry.year,
        expiry.month,
        expiry.day - offset,
        9,
      );
      if (!when.isAfter(DateTime.now())) continue;

      final id = _idFor(doc.id, offset);
      await _scheduleDocumentNotification(doc, id, offset, _localDateTime(when));
      await _verifyScheduled(id);
      ids.add(id);
    }
    doc.reminderIds = ids;
  }

  Future<List<int>> scheduleExpiry(
    DocItem doc, {
    List<int> offsets = const [30, 7, 1],
  }) async {
    await init();

    final expiry = doc.expiryDate;
    if (expiry == null) {
      await cancelFor(doc);
      return <int>[];
    }

    await _requireExactAlarm();
    await cancelFor(doc);

    final ids = <int>[];
    for (final offset in offsets) {
      final when = DateTime(
        expiry.year,
        expiry.month,
        expiry.day - offset,
        9,
      );
      if (!when.isAfter(DateTime.now())) continue;

      final id = _idFor(doc.id, offset);
      await _scheduleDocumentNotification(
        doc,
        id,
        offset,
        _localDateTime(when),
      );
      await _verifyScheduled(id);
      ids.add(id);
    }
    return ids;
  }

  Future<void> _scheduleDocumentNotification(
    DocItem doc,
    int id,
    int offset,
    tz.TZDateTime when,
  ) async {
    await _plugin.zonedSchedule(
      id,
      '${doc.title} expires soon',
      offset == 1
          ? 'Expires tomorrow. Tap to review your document.'
          : 'Expires in $offset days. Tap to review your document.',
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'expiry_reminders_v3',
          'Document expiry reminders',
          channelDescription: 'Local alerts before a document expires',
          icon: 'notification_icon',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: doc.id,
    );
  }

  Future<void> scheduleTask(TaskItem task) async {
    await init();
    if (task.completed || !task.notify) {
      await cancelTask(task);
      return;
    }
    await _requireExactAlarm();
    await cancelTask(task);

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'task_reminders_v3',
        'Tasks & reminders',
        channelDescription: 'Local alerts for personal tasks',
        icon: 'notification_icon',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
      iOS: DarwinNotificationDetails(),
    );

    final body = task.notes.trim().isEmpty
        ? 'Tap to open your reminder.'
        : task.notes.trim();

    var due = task.dueAt;
    if (!task.hasTime) {
      due = DateTime(due.year, due.month, due.day, 9);
    }

    var when = _localDateTime(due);
    final now = tz.TZDateTime.now(tz.local);

    if (task.repeat == TaskRepeat.once) {
      if (!when.isAfter(now)) return;
      await _plugin.zonedSchedule(
        task.notificationId,
        task.title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: task.id,
      );
      await _verifyScheduled(task.notificationId);
      return;
    }

    // For recurring reminders we calculate the first future occurrence and
    // then let the plugin repeat using the correct calendar component.
    if (task.repeat == TaskRepeat.daily) {
      while (!when.isAfter(now)) {
        when = when.add(const Duration(days: 1));
      }
    } else if (task.repeat == TaskRepeat.weekly) {
      while (!when.isAfter(now)) {
        when = when.add(const Duration(days: 7));
      }
    } else {
      while (!when.isAfter(now)) {
        final nextMonth = when.month == 12 ? 1 : when.month + 1;
        final nextYear = when.month == 12 ? when.year + 1 : when.year;
        final lastDay = DateTime(nextYear, nextMonth + 1, 0).day;
        final day = when.day > lastDay ? lastDay : when.day;
        when = tz.TZDateTime(
          tz.local,
          nextYear,
          nextMonth,
          day,
          when.hour,
          when.minute,
        );
      }
    }

    final component = switch (task.repeat) {
      TaskRepeat.daily => DateTimeComponents.time,
      TaskRepeat.weekly => DateTimeComponents.dayOfWeekAndTime,
      TaskRepeat.monthly => DateTimeComponents.dayOfMonthAndTime,
      TaskRepeat.once => null,
    };

    await _plugin.zonedSchedule(
      task.notificationId,
      task.title,
      body,
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: component,
      payload: task.id,
    );
    await _verifyScheduled(task.notificationId);
  }

  Future<void> _verifyScheduled(int id) async {
    final pending = await _plugin.pendingNotificationRequests();
    if (!pending.any((request) => request.id == id)) {
      throw StateError('Android did not retain scheduled notification $id.');
    }
  }

  Future<void> cancelFor(DocItem doc) async {
    await init();
    for (final id in doc.reminderIds) {
      await _plugin.cancel(id);
    }
    for (final offset in const [30, 7, 1]) {
      await _plugin.cancel(_idFor(doc.id, offset));
    }
  }

  Future<void> cancelTask(TaskItem task) async {
    await init();
    await _plugin.cancel(task.notificationId);
  }

  int _stableId(String value) {
    var hash = 2166136261;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  int _idFor(String docId, int offset) =>
      (_stableId(docId) ^ (offset * 7919)) & 0x7fffffff;
}
