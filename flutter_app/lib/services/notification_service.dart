import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/doc_item.dart';
import '../models/task_item.dart';
import '../utils/constants.dart';
import 'storage_service.dart';

@pragma('vm:entry-point')
void notificationActionBackground(NotificationResponse response) {
  // Keep the background handler deliberately small and independent of the
  // Flutter UI. Android can invoke this callback while the app process is
  // not running.
  if (response.actionId != 'stop_late_timer') return;

  unawaited(_stopLateTimerAndCompleteTask(
    plugin: FlutterLocalNotificationsPlugin(),
    pluginNeedsInit: true,
    payload: response.payload,
    tappedNotificationId: response.id,
  ));
}

/// Handles the STOP action on the overdue chronometer notification: marks
/// the underlying task as completed (so it is never rescheduled again) and
/// removes both the ongoing "late" notification and the original one-shot
/// alert, if it's still around. Shared by the foreground and background
/// response handlers so behaviour is identical whether the app is open,
/// backgrounded, or fully killed.
Future<void> _stopLateTimerAndCompleteTask({
  required FlutterLocalNotificationsPlugin plugin,
  required bool pluginNeedsInit,
  required String? payload,
  required int? tappedNotificationId,
}) async {
  if (pluginNeedsInit) {
    try {
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/notification_icon'),
        ),
      );
    } catch (error) {
      debugPrint('Could not init plugin from background: $error');
    }
  }

  String? taskId;
  if (payload != null && payload.startsWith('late:')) {
    taskId = payload.substring('late:'.length);
  }

  int? lateId = tappedNotificationId;
  int? alertId;

  try {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(TaskItemAdapter());
    }
    final box = Hive.isBoxOpen(HiveBoxes.tasks)
        ? Hive.box<TaskItem>(HiveBoxes.tasks)
        : await Hive.openBox<TaskItem>(HiveBoxes.tasks);

    final task = taskId == null ? null : box.get(taskId);
    if (task != null) {
      alertId = task.notificationId;
      lateId = task.lateNotificationId;
      if (!task.completed) {
        task.completed = true;
        await box.put(task.id, task);
      }
    }
  } catch (error) {
    debugPrint('Could not mark task complete from STOP action: $error');
  }

  try {
    if (lateId != null) await plugin.cancel(lateId);
    if (alertId != null) await plugin.cancel(alertId);
  } catch (error) {
    debugPrint('Could not cancel notification(s) after STOP: $error');
  }
}

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

  /// Ongoing, non-swipeable notification with a live Android chronometer
  /// (the "how long since due" ticking timer) — same pattern delivery apps
  /// like Flipkart use for "your order is late" alerts.
  static const AndroidNotificationChannel _lateChannel =
      AndroidNotificationChannel(
    'task_late_timer_v1',
    'Overdue timer',
    description:
        'A persistent, ongoing timer that counts up while a task is overdue',
    importance: Importance.high,
  );

  /// Flipkart-style blue used for the colorized overdue timer notification.
  static const Color _lateColor = Color(0xFF2A76D2);

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

      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
        onDidReceiveBackgroundNotificationResponse: notificationActionBackground,
      );

      final android = _android;
      await android?.createNotificationChannel(_expiryChannel);
      await android?.createNotificationChannel(_taskChannel);
      await android?.createNotificationChannel(_lateChannel);
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

  static const MethodChannel _exactAlarmChannel =
      MethodChannel('com.docwallet.wallet/exact_alarm');

  /// Opens the Android system page for this app's Exact Alarm access.
  /// Android controls this permission; the app cannot grant it itself.
  Future<bool> openExactAlarmSettings() async {
    try {
      final opened = await _exactAlarmChannel.invokeMethod<bool>(
        'openExactAlarmSettings',
      );
      return opened == true;
    } catch (error) {
      debugPrint('Could not open Exact Alarm settings: $error');
      return false;
    }
  }

  /// Ensures both notification and precise-alarm access are available.
  /// If Exact Alarm is missing, Android Settings is opened automatically.
  Future<bool> ensureReminderAccess({bool openSettings = true}) async {
    await init();
    final notifications = await requestPermissions();
    if (!notifications) return false;
    if (await exactAlarmPermissionGranted()) return true;
    if (openSettings) {
      await openExactAlarmSettings();
    }
    return false;
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

  void _onNotificationResponse(NotificationResponse response) {
    if (response.actionId == 'stop_late_timer') {
      unawaited(_stopLateTimerAndCompleteTask(
        plugin: _plugin,
        pluginNeedsInit: false,
        payload: response.payload,
        tappedNotificationId: response.id,
      ));
      return;
    }
  }

  AndroidBitmap<Object>? _taskImageBitmap(TaskItem task) {
    final path = task.imagePath;
    if (path == null || path.trim().isEmpty) return null;
    try {
      if (!File(path).existsSync()) return null;
      return FilePathAndroidBitmap(path);
    } catch (_) {
      return null;
    }
  }

  StyleInformation? _taskStyle(TaskItem task) {
    final path = task.imagePath;
    if (path == null || path.trim().isEmpty) return null;
    try {
      if (!File(path).existsSync()) return null;
      return BigPictureStyleInformation(
        FilePathAndroidBitmap(path),
        largeIcon: FilePathAndroidBitmap(path),
        contentTitle: task.title,
        summaryText: task.notes.trim().isEmpty ? null : task.notes.trim(),
        hideExpandedLargeIcon: false,
      );
    } catch (_) {
      return null;
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
    // Arm the ongoing "how late" chronometer independently of the one-shot
    // alert below, so it still shows up even if scheduling the alert fails.
    unawaited(scheduleLateTimer(task).catchError((Object error) {
      debugPrint('Late timer scheduling failed: $error');
    }));

    final imageBitmap = _taskImageBitmap(task);
    final imageStyle = _taskStyle(task);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'task_reminders_v3',
        'Tasks & reminders',
        channelDescription: 'Local alerts for personal tasks',
        icon: 'notification_icon',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        largeIcon: imageBitmap,
        styleInformation: imageStyle,
      ),
      iOS: const DarwinNotificationDetails(),
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

  NotificationDetails _lateNotificationDetails(TaskItem task) {
    final due = task.hasTime
        ? task.dueAt
        : DateTime(task.dueAt.year, task.dueAt.month, task.dueAt.day, 9);
    final imageBitmap = _taskImageBitmap(task);
    final imageStyle = _taskStyle(task);
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'task_late_timer_v1',
        'Overdue timer',
        channelDescription:
            'A persistent, ongoing timer that counts up while a task is overdue',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'notification_icon',
        // Non-swipeable, stays until the user taps STOP.
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
        // Native Android "chronometer" — a live MM:SS/HH:MM ticking clock
        // rendered by the OS itself, so it keeps counting even if the app
        // is closed. `when` is the original due time, so the chronometer
        // shows exactly how late the task is.
        showWhen: true,
        when: due.millisecondsSinceEpoch,
        usesChronometer: true,
        chronometerCountDown: false,
        // Blue, colorized card — same visual language as delivery-tracking
        // notifications (Flipkart, Swiggy, etc.).
        colorized: true,
        color: _lateColor,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
        largeIcon: imageBitmap,
        styleInformation: imageStyle ??
            const BigTextStyleInformation(
              'Still pending. Tap STOP once you have handled it.',
            ),
        actions: const [
          AndroidNotificationAction(
            'stop_late_timer',
            'STOP',
            cancelNotification: true,
            showsUserInterface: false,
          ),
        ],
      ),
      iOS: const DarwinNotificationDetails(
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
  }

  /// Starts (or re-arms) the ongoing "you're late" timer for a one-off task.
  /// It is scheduled to appear the moment the task becomes due and then
  /// counts up on its own — no app process needed to keep it alive.
  Future<void> scheduleLateTimer(TaskItem task) async {
    await init();
    await cancelLateTimer(task);

    if (task.completed || !task.notify) return;
    // Recurring tasks reset every cycle, so a single overdue timer doesn't
    // map cleanly onto them — keep this for one-off reminders.
    if (task.repeat != TaskRepeat.once) return;

    await _requireExactAlarm();

    var due = task.dueAt;
    if (!task.hasTime) due = DateTime(due.year, due.month, due.day, 9);

    final when = _localDateTime(due);
    final now = tz.TZDateTime.now(tz.local);

    if (!when.isAfter(now)) {
      // Already overdue right now — show it immediately, chronometer will
      // correctly reflect elapsed time since `due`.
      await _plugin.show(
        task.lateNotificationId,
        task.title,
        "You're late on this reminder",
        _lateNotificationDetails(task),
        payload: 'late:${task.id}',
      );
      return;
    }

    await _plugin.zonedSchedule(
      task.lateNotificationId,
      task.title,
      "You're late on this reminder",
      when,
      _lateNotificationDetails(task),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'late:${task.id}',
    );
  }

  Future<void> cancelLateTimer(TaskItem task) async {
    await init();
    await _plugin.cancel(task.lateNotificationId);
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
    await _plugin.cancel(task.lateNotificationId);
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
