import 'package:flutter/material.dart';
// Notification theme: green for active reminders, red for overdue reminders.
const _activeNotificationColor = Color(0xFF2E7D32);
const _lateNotificationColor = Color(0xFFD32F2F);
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/doc_item.dart';
import '../models/task_item.dart';
import '../services/storage_service.dart';

/// Reliable, fully local scheduled notifications.
///
/// Android requires notification permission on Android 13+ and exact-alarm
/// access for exact, on-time alarms. Both are requested during app startup.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  bool _timezoneReady = false;

  static const _expiryChannel = AndroidNotificationDetails(
    'expiry_reminders_v2',
    'Document expiry reminders',
    channelDescription: 'Alerts before a document expires',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );

  Future<void> init() async {
    if (_ready) return;

    tzdata.initializeTimeZones();

    // timezone's default location is UTC. Explicitly bind it to the device's
    // actual OS timezone so a 9:00 reminder means 9:00 local time.
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      final name = info.identifier;
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // Keep timezone package's current location if the platform lookup fails.
    }
    _timezoneReady = true;

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // If Android launched the app because the user tapped an ongoing
    // notification while the app was not running, dismiss that notification
    // immediately as the user's explicit stop action.
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && response != null) {
        await _onNotificationTapped(response);
      }
    } catch (_) {}

    _ready = true;
  }

  /// A due task becomes an ongoing Android notification. It cannot be
  /// swiped away; tapping it is the intentional "Done / Stop" action.
  /// We cancel it immediately and let Android open the app normally.
  Future<void> _onNotificationTapped(NotificationResponse response) async {
    final payload = response.payload;
    try {
      if (payload != null && payload.isNotEmpty) {
        final task = StorageService.instance.tasks.get(payload);
        if (task != null) {
          await _plugin.cancel(task.notificationId);
          return;
        }
      }
      final id = response.id;
      if (id != null) await _plugin.cancel(id);
    } catch (_) {
      final id = response.id;
      if (id != null) await _plugin.cancel(id);
    }
  }

  Future<void> requestPermissions() async {
    await init();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await android?.requestNotificationsPermission();

    // Exact alarms are used only for user-created reminders and expiry alerts.
    // If the device does not expose this API, scheduling still falls back to
    // the normal alarm path.
    try {
      await android?.requestExactAlarmsPermission();
    } catch (_) {}

    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Rebuilds all scheduled notifications from the local Hive records.
  ///
  /// This repairs schedules after an app update, reinstall/restore, or a
  /// device that cleared scheduled alarms.
  Future<void> rescheduleAll() async {
    await init();

    for (final doc in StorageService.instance.documents.values.toList()) {
      try {
        final ids = await scheduleExpiry(doc);
        doc.reminderIds = ids;
        await doc.save();
      } catch (_) {}
    }

    for (final task in StorageService.instance.tasks.values.toList()) {
      try {
        await scheduleTask(task);
      } catch (_) {}
    }
  }

  Future<List<int>> scheduleExpiry(
    DocItem doc, {
    List<int> offsets = const [30, 7, 1],
  }) async {
    await init();
    await cancelFor(doc);

    final expiry = doc.expiryDate;
    if (expiry == null) return [];

    final ids = <int>[];
    for (final offset in offsets) {
      final when = DateTime(
        expiry.year,
        expiry.month,
        expiry.day - offset,
        9,
        0,
      );

      if (!when.isAfter(DateTime.now())) continue;

      final id = _idFor('doc:${doc.id}:$offset');
      await _schedule(
        id: id,
        title: '${doc.title} expires soon',
        body: offset == 1
            ? 'Expires tomorrow. Tap to review your document.'
            : 'Expires in $offset days. Tap to review your document.',
        when: when,
        details: const NotificationDetails(
          android: _expiryChannel,
          iOS: DarwinNotificationDetails(),
        ),
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
  }

  Future<void> scheduleTask(TaskItem task) async {
    await init();
    await cancelTask(task);

    if (task.completed || !task.notify) return;

    final body = task.notes.trim().isEmpty
        ? 'Reminder is due. Tap this notification to stop the timer.'
        : '${task.notes}\nTap this notification to stop the timer.';

    if (task.repeat == TaskRepeat.once) {
      final details = _taskDetails(task, body);
      if (task.dueAt.isAfter(DateTime.now())) {
        await _schedule(
          id: task.notificationId,
          title: task.title,
          body: body,
          when: task.dueAt,
          details: details,
          payload: task.id,
        );
      } else {
        // If a past reminder is restored/rescheduled, show the late alert
        // immediately instead of silently losing it.
        await _showLateTask(task, body);
      }
      return;
    }

    final component = switch (task.repeat) {
      TaskRepeat.daily => DateTimeComponents.time,
      TaskRepeat.weekly => DateTimeComponents.dayOfWeekAndTime,
      TaskRepeat.monthly => DateTimeComponents.dayOfMonthAndTime,
      TaskRepeat.once => null,
    };

    var when = tz.TZDateTime.from(task.dueAt, tz.local);
    final now = tz.TZDateTime.now(tz.local);

    // Move the first occurrence into the future without changing its local
    // clock time.
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
        final nextMonth = when.month == 12 ? when.year + 1 : when.year;
        final nextMonthNumber = when.month == 12 ? 1 : when.month + 1;
        final lastDay = DateTime(nextMonth, nextMonthNumber + 1, 0).day;
        when = tz.TZDateTime(
          tz.local,
          nextMonth,
          nextMonthNumber,
          when.day.clamp(1, lastDay),
          when.hour,
          when.minute,
        );
      }
    }

    await _plugin.zonedSchedule(
      task.notificationId,
      task.title,
      body,
      when,
      _taskDetails(task, body),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: component,
      payload: task.id,
    );
  }

  NotificationDetails _taskDetails(TaskItem task, String body) {
    final hasImage = task.imagePath.isNotEmpty && File(task.imagePath).existsSync();
    final style = hasImage
        ? BigPictureStyleInformation(
            FilePathAndroidBitmap(task.imagePath),
            hideExpandedLargeIcon: false,
            contentTitle: task.title,
            summaryText: body,
          )
        : null;

    return NotificationDetails(
      android: AndroidNotificationDetails(
        'active_task_reminders_v3',
        'Active reminders',
        channelDescription: 'Important reminders that stay visible until tapped',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        subText: 'LATE • Tap to stop the timer',
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
        usesChronometer: true,
        chronometerCountDown: false,
        when: task.dueAt.millisecondsSinceEpoch,
        largeIcon: hasImage ? FilePathAndroidBitmap(task.imagePath) : null,
        styleInformation: style,
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }

  Future<void> _showLateTask(TaskItem task, String body) async {
    await _plugin.show(
      task.notificationId,
      task.title,
      body,
      _taskDetails(task, body),
      payload: task.id,
    );
  }

  Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required NotificationDetails details,
    required String payload,
  }) async {
    if (!_timezoneReady) await init();

    final scheduled = tz.TZDateTime.from(when, tz.local);
    if (!scheduled.isAfter(tz.TZDateTime.now(tz.local))) return;

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } on Exception catch (e) {
      // Some Android devices do not grant exact-alarm access. Keep reminders
      // working with an inexact alarm rather than dropping them completely.
      if (kDebugMode) {
        debugPrint('Exact notification failed: $e');
      }
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    }
  }

  Future<void> cancelTask(TaskItem task) async {
    await init();
    await _plugin.cancel(task.notificationId);
  }

  /// Stable 31-bit FNV-1a hash. Unlike Dart's String.hashCode, this remains
  /// stable across app launches, making cancellation/recovery reliable.
  int _idFor(String value) {
    var hash = 2166136261;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}
