import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class ReminderNotifications {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const int _firstReminderId = 7400;
  static const int _scheduledReminderCount = 30;
  static const int _minimumPendingReminders = 20;
  static const int _reminderHour = 20;
  static const String _channelId = 'quran_reminders';
  static const String _channelName = 'Quran reminders';

  static const List<String> _messages = [
    'Have you spent even 5 minutes with the Quran today?',
    'Even one page today keeps your connection with the Quran alive.',
    'Pick up the Quran for just a few minutes today. Start small.',
    'A quick revision today is better than a long gap tomorrow.',
    'The Quran is your companion.',
    'Read a little. Revise a little. Stay connected.',
    'Even one ayah today counts.',
    "Don't break your connection with the Quran today.",
    '5 quiet minutes with the Quran before the day ends?',
    'Revision today makes memorisation stronger tomorrow.',
  ];

  static Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) return;

    try {
      tz.initializeTimeZones();
      await _setLocalTimezone();

      await _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
          macOS: DarwinInitializationSettings(),
        ),
      );

      final permitted = await _requestPermission();
      if (!permitted) return;

      await _scheduleIfNeeded();
    } catch (e) {
      debugPrint('[NOTIFICATIONS] Reminder setup failed: $e');
    }
  }

  static Future<void> _setLocalTimezone() async {
    try {
      final timezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezone.identifier));
    } catch (e) {
      debugPrint('[NOTIFICATIONS] Falling back to timezone default: $e');
    }
  }

  static Future<bool> _requestPermission() async {
    if (!Platform.isAndroid) return true;

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final permitted = await androidPlugin?.requestNotificationsPermission();
    return permitted ?? true;
  }

  static Future<void> _scheduleIfNeeded() async {
    final pending = await _notifications.pendingNotificationRequests();
    final pendingReminderCount = pending
        .where(
          (notification) =>
              notification.id >= _firstReminderId &&
              notification.id < _firstReminderId + _scheduledReminderCount,
        )
        .length;

    if (pendingReminderCount >= _minimumPendingReminders) return;

    for (var i = 0; i < _scheduledReminderCount; i++) {
      await _notifications.cancel(id: _firstReminderId + i);
    }

    final firstReminder = _nextReminderTime();
    for (var i = 0; i < _scheduledReminderCount; i++) {
      final scheduledDate = firstReminder.add(Duration(days: i * 2));
      final message = _messages[i % _messages.length];

      await _notifications.zonedSchedule(
        id: _firstReminderId + i,
        title: 'Quran reminder',
        body: message,
        scheduledDate: scheduledDate,
        notificationDetails: _notificationDetails(message),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'quran_reminder',
      );
    }
  }

  static tz.TZDateTime _nextReminderTime() {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      _reminderHour,
    );

    if (!scheduled.isAfter(now.add(const Duration(minutes: 1)))) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }

  static NotificationDetails _notificationDetails(String message) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription:
            'Gentle reminders to keep your connection with the Quran.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        color: const Color(0xFF025C32),
        styleInformation: BigTextStyleInformation(message),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    );
  }
}
