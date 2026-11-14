import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import 'localization/app_localizations.dart';
import 'notification_time_rules.dart';

abstract interface class ReminderService {
  bool get isSupported;
  Future<void> initialize();
  Future<void> enableDaily({
    required int hour,
    required int minute,
    required String title,
    required String body,
    bool quietHoursEnabled = false,
    int quietStartMinutes = 22 * 60,
    int quietEndMinutes = 7 * 60,
    bool soundEnabled = true,
    bool vibrationEnabled = true,
    bool privatePreview = false,
    String language = 'en',
  });
  Future<void> scheduleDaily({
    required int hour,
    required int minute,
    required String title,
    required String body,
    bool quietHoursEnabled = false,
    int quietStartMinutes = 22 * 60,
    int quietEndMinutes = 7 * 60,
    bool soundEnabled = true,
    bool vibrationEnabled = true,
    bool privatePreview = false,
    String language = 'en',
  });
  Future<void> cancel();
}

class LocalReminderService implements ReminderService {
  LocalReminderService({
    FlutterLocalNotificationsPlugin? notifications,
  }) : _notifications = notifications ?? FlutterLocalNotificationsPlugin();

  static const _notificationId = 401;
  final FlutterLocalNotificationsPlugin _notifications;
  bool _initialized = false;
  bool _timeZonesInitialized = false;

  @override
  bool get isSupported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<void> initialize() async {
    if (!isSupported) return;
    if (!_timeZonesInitialized) {
      timezone_data.initializeTimeZones();
      _timeZonesInitialized = true;
    }
    final localZone = await FlutterTimezone.getLocalTimezone();
    timezone.setLocalLocation(timezone.getLocation(localZone.identifier));
    if (_initialized) return;

    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/launcher_icon'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  @override
  Future<void> enableDaily({
    required int hour,
    required int minute,
    required String title,
    required String body,
    bool quietHoursEnabled = false,
    int quietStartMinutes = 22 * 60,
    int quietEndMinutes = 7 * 60,
    bool soundEnabled = true,
    bool vibrationEnabled = true,
    bool privatePreview = false,
    String language = 'en',
  }) async {
    await initialize();
    if (!isSupported) {
      throw UnsupportedError('Local reminders are not supported here.');
    }

    final permitted = switch (defaultTargetPlatform) {
      TargetPlatform.android => await _notifications
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission() ??
          false,
      TargetPlatform.iOS => await _notifications
              .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false,
      _ => false,
    };
    if (!permitted) {
      await _notifications.cancel(id: _notificationId);
      throw const ReminderPermissionDeniedException();
    }
    await scheduleDaily(
      hour: hour,
      minute: minute,
      title: title,
      body: body,
      quietHoursEnabled: quietHoursEnabled,
      quietStartMinutes: quietStartMinutes,
      quietEndMinutes: quietEndMinutes,
      soundEnabled: soundEnabled,
      vibrationEnabled: vibrationEnabled,
      privatePreview: privatePreview,
      language: language,
    );
  }

  @override
  Future<void> scheduleDaily({
    required int hour,
    required int minute,
    required String title,
    required String body,
    bool quietHoursEnabled = false,
    int quietStartMinutes = 22 * 60,
    int quietEndMinutes = 7 * 60,
    bool soundEnabled = true,
    bool vibrationEnabled = true,
    bool privatePreview = false,
    String language = 'en',
  }) async {
    await initialize();
    if (!isSupported) {
      throw UnsupportedError('Local reminders are not supported here.');
    }
    if (quietHoursEnabled && quietStartMinutes == quietEndMinutes) {
      await _notifications.cancel(id: _notificationId);
      return;
    }

    final now = timezone.TZDateTime.now(timezone.local);
    final selectedMinutes = hour * 60 + minute;
    var scheduledHour = hour;
    var scheduledMinute = minute;
    var dayOffset = 0;
    if (quietHoursEnabled &&
        NotificationTimeRules.isWithinQuietHours(
          selectedMinutes,
          quietStartMinutes,
          quietEndMinutes,
        )) {
      scheduledHour = quietEndMinutes ~/ 60;
      scheduledMinute = quietEndMinutes % 60;
      if (quietStartMinutes > quietEndMinutes &&
          selectedMinutes >= quietStartMinutes) {
        dayOffset = 1;
      }
    }
    var scheduled = timezone.TZDateTime(
      timezone.local,
      now.year,
      now.month,
      now.day + dayOffset,
      scheduledHour,
      scheduledMinute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    final displayedTitle = privatePreview
        ? AppLocalizations.forLanguageCode(language)
            .text('privateTitle', domain: 'notifications')
        : title;
    final displayedBody = privatePreview
        ? AppLocalizations.forLanguageCode(language)
            .text('privateBody', domain: 'notifications')
        : body;
    final channelId = 'skin_care_${soundEnabled ? 'sound' : 'silent'}_'
        '${vibrationEnabled ? 'vibrate' : 'still'}';
    await _notifications.zonedSchedule(
      id: _notificationId,
      title: displayedTitle,
      body: displayedBody,
      scheduledDate: scheduled,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          AppLocalizations.forLanguageCode(language)
              .text('dailyChannelName', domain: 'notifications'),
          channelDescription: AppLocalizations.forLanguageCode(language)
              .text('dailyChannelDescription', domain: 'notifications'),
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          playSound: soundEnabled,
          enableVibration: vibrationEnabled,
        ),
        iOS: DarwinNotificationDetails(presentSound: soundEnabled),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> cancel() async {
    if (!isSupported) return;
    await initialize();
    await _notifications.cancel(id: _notificationId);
  }
}

class ReminderPermissionDeniedException implements Exception {
  const ReminderPermissionDeniedException();

  @override
  String toString() => 'Notification permission was denied.';
}
