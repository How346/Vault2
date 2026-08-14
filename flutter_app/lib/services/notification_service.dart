import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/doc_item.dart';
import '../models/task_item.dart';
import 'storage_service.dart';

/// Local scheduled notifications. No network/push service is required.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  AndroidScheduleMode _scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;

  static const AndroidNotificationChannel _expiryChannel =
      AndroidNotificationChannel(
    'expiry_reminders_v2',
    'Document expiry reminders',
    description: 'Local alerts before a document expires',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel _taskChannel =
      AndroidNotificationChannel(
    'task_reminders_v2',
    'Tasks & reminders',
    description: 'Local alerts for personal tasks',
    importance: Importance.high,
  );

  // Separate channel for the diagnostic notification. Using a fresh channel
  // prevents an old user's muted channel from making the test appear broken.
  static const AndroidNotificationChannel _testChannel =
      AndroidNotificationChannel(
    'wallet_test_v3',
    'Wallet test notifications',
    description: 'Immediate notification used to verify notification delivery',
    importance: Importance.max,
  );

  Future<void> init() async {
    if (_ready) return;

    tzdata.initializeTimeZones();

    // Use the device's actual IANA timezone instead of assuming India/UTC.
    // This keeps reminders correct when the phone travels or uses DST.
    try {
      final deviceZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(deviceZone.identifier));
    } catch (_) {
      // UTC is the safe fallback if the native timezone cannot be read.
      tz.setLocalLocation(tz.UTC);
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

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_expiryChannel);
    await android?.createNotificationChannel(_taskChannel);
    await android?.createNotificationChannel(_testChannel);

    // Exact alarms are required for reminders that must fire at the selected
    // minute. If the special Android permission has not yet been granted,
    // keep a safe inexact fallback until the user enables it.
    try {
      final exactAllowed = await android?.canScheduleExactNotifications();
      _scheduleMode = exactAllowed == true
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
    } catch (_) {
      _scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;
    }

    _ready = true;
  }

  Future<bool> exactAlarmPermissionGranted() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      return await android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestPermissions({bool requestExactAlarm = false}) async {
    await init();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    // Android 13+: notifications are a runtime permission. Always ask at the
    // first explicit enable action; scheduling alone cannot grant it.
    await android?.requestNotificationsPermission();

    // Android 14+ can deny SCHEDULE_EXACT_ALARM by default. Exact alarms are
    // used when available so reminders are delivered at the selected minute.
    // Only open the system settings from an explicit user action.
    if (requestExactAlarm) {
      try {
        final exactAllowed = await android?.canScheduleExactNotifications();
        if (exactAllowed != true) {
          await android?.requestExactAlarmsPermission();
        }
      } catch (_) {}
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Refresh the scheduling mode after permission changes.
    try {
      final exactAllowed = await android?.canScheduleExactNotifications();
      _scheduleMode = exactAllowed == true
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
    } catch (_) {
      _scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;
    }
  }

  /// Shows an immediate notification. Useful for verifying that the Android
  /// notification permission/channel is working before testing a future date.
  Future<bool> showTestNotification() async {
    await init();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    // The test action must work even if the user skipped the startup prompt.
    // Ask for Android 13+ notification permission immediately before showing.
    final permissionResult = await android?.requestNotificationsPermission();
    final enabled = await android?.areNotificationsEnabled();

    if (enabled == false || permissionResult == false) {
      return false;
    }

    await _plugin.show(
      987654,
      'Wallet',
      'Test notification — reminders are enabled.',
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

  /// Rebuilds OS schedules from the local database after app start.
  /// Android stores alarms outside the Flutter process, but this also repairs
  /// schedules that were lost after an update, restore, or migration.
  Future<void> rescheduleStoredNotifications() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final enabled = await android?.areNotificationsEnabled();
    if (enabled == false) return;

    final storage = StorageService.instance;
    for (final doc in storage.documents.values) {
      try {
        final ids = await scheduleExpiry(doc);
        doc.reminderIds = ids;
        await doc.save();
      } catch (_) {
        // One broken record must never prevent other reminders from loading.
      }
    }

    for (final task in storage.tasks.values) {
      try {
        await scheduleTask(task);
      } catch (_) {
        // Continue scheduling the remaining tasks.
      }
    }
  }

  Future<void> scheduleAllForDocument(DocItem doc) async {
    await init();
    await cancelFor(doc);
    await _refreshScheduleMode(requestExact: true);

    final expiry = doc.expiryDate;
    if (expiry == null) {
      doc.reminderIds = <int>[];
      return;
    }

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
      await _plugin.zonedSchedule(
        id,
        '${doc.title} expires soon',
        offset == 1
            ? 'Expires tomorrow. Tap to review your document.'
            : 'Expires in $offset days. Tap to review your document.',
        tz.TZDateTime(
          tz.local,
          when.year,
          when.month,
          when.day,
          when.hour,
          when.minute,
        ),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'expiry_reminders_v2',
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
        androidScheduleMode: _scheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: doc.id,
      );
      ids.add(id);
    }

    doc.reminderIds = ids;
  }

  /// Backwards-compatible name used by the wallet controller.
  Future<List<int>> scheduleExpiry(
    DocItem doc, {
    List<int> offsets = const [30, 7, 1],
  }) async {
    await init();
    await cancelFor(doc);
    await _refreshScheduleMode(requestExact: true);

    final expiry = doc.expiryDate;
    if (expiry == null) return <int>[];

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
      await _plugin.zonedSchedule(
        id,
        '${doc.title} expires soon',
        offset == 1
            ? 'Expires tomorrow. Tap to review your document.'
            : 'Expires in $offset days. Tap to review your document.',
        tz.TZDateTime(
          tz.local,
          when.year,
          when.month,
          when.day,
          when.hour,
          when.minute,
        ),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'expiry_reminders_v2',
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
        androidScheduleMode: _scheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: doc.id,
      );
      ids.add(id);
    }
    return ids;
  }

  Future<void> cancelFor(DocItem doc) async {
    await init();
    for (final id in doc.reminderIds) {
      await _plugin.cancel(id);
    }
    // Also cancel deterministic IDs even if an older database record lost
    // its reminderIds during migration.
    for (final offset in const [30, 7, 1]) {
      await _plugin.cancel(_idFor(doc.id, offset));
    }
  }

  Future<void> _refreshScheduleMode({bool requestExact = false}) async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      var exactAllowed = await android?.canScheduleExactNotifications() ?? false;
      if (!exactAllowed && requestExact) {
        await android?.requestExactAlarmsPermission();
        exactAllowed = await android?.canScheduleExactNotifications() ?? false;
      }
      _scheduleMode = exactAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
    } catch (_) {
      _scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;
    }
  }

  Future<void> scheduleTask(TaskItem task) async {
    await init();
    await cancelTask(task);
    await _refreshScheduleMode(requestExact: true);
    if (task.completed || !task.notify) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'task_reminders_v2',
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

    final body =
        task.notes.trim().isEmpty ? 'Tap to open your reminder.' : task.notes;

    var due = task.dueAt;
    if (!task.hasTime) {
      due = DateTime(due.year, due.month, due.day, 9);
    }
    if (!due.isAfter(DateTime.now()) && task.repeat == TaskRepeat.once) return;

    if (task.repeat == TaskRepeat.once) {
      await _plugin.zonedSchedule(
        task.notificationId,
        task.title,
        body,
        tz.TZDateTime(
          tz.local,
          due.year,
          due.month,
          due.day,
          due.hour,
          due.minute,
        ),
        details,
        androidScheduleMode: _scheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: task.id,
      );
      return;
    }

    var when = tz.TZDateTime(
      tz.local,
      due.year,
      due.month,
      due.day,
      due.hour,
      due.minute,
    );
    final now = tz.TZDateTime.now(tz.local);

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
        final day = when.day;
        final lastDay = DateTime(nextYear, nextMonth + 1, 0).day;
        when = tz.TZDateTime(
          tz.local,
          nextYear,
          nextMonth,
          day > lastDay ? lastDay : day,
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
      androidScheduleMode: _scheduleMode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: component,
      payload: task.id,
    );
  }

  Future<void> cancelTask(TaskItem task) async {
    await init();
    await _plugin.cancel(task.notificationId);
  }

  int _stableId(String value) {
    // Stable across app launches; Dart's String.hashCode is not a persistence
    // contract and can change between processes.
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
