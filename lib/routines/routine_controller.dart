import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../localization/app_localizations.dart';
import '../notification_time_rules.dart';
import 'home_widget_bridge.dart';
import 'routine_models.dart';

abstract interface class RoutineScheduler {
  bool get isSupported;
  Future<void> initialize(void Function(String? payload) onTap);
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<void> schedule(
    RoutineTask task,
    RoutineNotificationSettings settings, {
    required String language,
    required void Function(String? payload) onTap,
  });
  Future<void> cancelTask(String taskId);
  Future<void> cancelAllRoutineTasks(Iterable<String> taskIds);
  Future<void> previewAlert({
    required bool sound,
    required bool vibration,
    required String language,
    required String title,
    required String body,
    required void Function(String? payload) onTap,
  });
}

class LocalRoutineScheduler implements RoutineScheduler {
  LocalRoutineScheduler({
    FlutterLocalNotificationsPlugin? notifications,
  }) : _notifications = notifications ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _notifications;
  bool _initialized = false;
  bool _permissionGranted = false;
  bool _timeZonesInitialized = false;
  void Function(String? payload)? _onTap;

  @override
  Future<void> initialize(void Function(String? payload) onTap) async {
    _onTap = onTap;
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
      onDidReceiveNotificationResponse: (response) =>
          _onTap?.call(response.payload),
    );
    _initialized = true;
  }

  @override
  bool get isSupported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<bool> hasPermission() async {
    if (!isSupported) return false;
    await initialize(_onTap ?? (_) {});
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => await _notifications
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.areNotificationsEnabled() ??
          false,
      TargetPlatform.iOS => await _notifications
              .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin>()
              ?.checkPermissions()
              .then((permissions) => permissions?.isEnabled ?? false) ??
          false,
      _ => false,
    };
  }

  @override
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    await initialize(_onTap ?? (_) {});
    _permissionGranted = switch (defaultTargetPlatform) {
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
    return _permissionGranted;
  }

  @override
  Future<void> schedule(
    RoutineTask task,
    RoutineNotificationSettings settings, {
    required String language,
    required void Function(String? payload) onTap,
  }) async {
    await initialize(onTap);
    if (!isSupported) {
      throw UnsupportedError('Routine notifications are not supported here.');
    }
    await cancelTask(task.id);
    final isWeeklySummary = task.id == 'weekly-summary';
    final isScanReminder = task.id == 'ai-scan-reminder';
    if (!settings.masterEnabled ||
        !task.reminderEnabled ||
        task.weekdays.isEmpty) {
      return;
    }
    if (settings.quietHoursEnabled &&
        settings.quietStartMinutes == settings.quietEndMinutes) {
      return;
    }
    if (isWeeklySummary && !settings.weeklySummaryEnabled) return;
    if (isScanReminder && !settings.aiScanEnabled) return;
    if (!isWeeklySummary &&
        !isScanReminder &&
        (!settings.dailyEnabled || !_categoryEnabled(task, settings))) {
      return;
    }

    final channelId =
        'skin_routine_${settings.soundEnabled ? 'sound' : 'silent'}_'
        '${settings.vibrationEnabled ? 'vibrate' : 'still'}';
    for (final originalWeekday in task.weekdays.toSet()) {
      var weekday = originalWeekday;
      var reminderMinutes = task.reminderMinutes;
      if (settings.quietHoursEnabled &&
          NotificationTimeRules.isWithinQuietHours(
            reminderMinutes,
            settings.quietStartMinutes,
            settings.quietEndMinutes,
          )) {
        if (settings.quietStartMinutes > settings.quietEndMinutes &&
            reminderMinutes >= settings.quietStartMinutes) {
          weekday = weekday % 7 + 1;
        }
        reminderMinutes = settings.quietEndMinutes;
      }
      final reminder = _timeForNextWeekday(
        weekday,
        reminderMinutes,
      );
      final id = _notificationId(task.id, originalWeekday);
      final private = settings.privatePreview;
      final (titleKey, bodyKey, arguments) = _notificationContent(task);
      await _notifications.zonedSchedule(
        id: id,
        title: private
            ? _text(language, 'privateTitle')
            : _text(language, titleKey),
        body: private
            ? _text(language, 'privateBody')
            : _text(language, bodyKey, arguments: arguments),
        scheduledDate: reminder,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            _text(language, 'routineChannelName'),
            channelDescription: _text(language, 'routineChannelDescription'),
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            playSound: settings.soundEnabled,
            enableVibration: settings.vibrationEnabled,
          ),
          iOS: DarwinNotificationDetails(
            presentSound: settings.soundEnabled,
          ),
        ),
        payload: 'routine://${task.id}',
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  String _text(
    String language,
    String key, {
    Map<String, String> arguments = const {},
  }) =>
      AppLocalizations.forLanguageCode(language).text(
        key,
        domain: 'notifications',
        arguments: arguments,
      );

  bool _categoryEnabled(
    RoutineTask task,
    RoutineNotificationSettings settings,
  ) {
    final normalizedTitle = task.title.toLowerCase();
    if (task.id.contains('sunscreen') ||
        normalizedTitle.contains('sunscreen') ||
        normalizedTitle.contains('sun screen') ||
        normalizedTitle.contains('spf') ||
        normalizedTitle.contains('پارێزەری خۆر') ||
        normalizedTitle.contains('واقي الشمس')) {
      return settings.sunscreenEnabled;
    }
    if (task.id.contains('hydration') ||
        normalizedTitle.contains('hydration') ||
        normalizedTitle.contains('water') ||
        normalizedTitle.contains('ئاو') ||
        normalizedTitle.contains('ترطيب') ||
        normalizedTitle.contains('الماء')) {
      return settings.hydrationEnabled;
    }
    return switch (task.period) {
      RoutinePeriod.morning => settings.morningEnabled,
      RoutinePeriod.evening || RoutinePeriod.bedtime => settings.eveningEnabled,
      RoutinePeriod.afternoon => true,
    };
  }

  (String, String, Map<String, String>) _notificationContent(
    RoutineTask task,
  ) {
    if (task.id == 'weekly-summary') {
      return (
        'weeklySummaryTitle',
        'weeklySummaryBody',
        const {},
      );
    }
    if (task.id == 'ai-scan-reminder') {
      return (
        'scanCheckinTitle',
        'scanCheckinBody',
        const {},
      );
    }
    final title = task.title.toLowerCase();
    if (task.id.contains('sunscreen') ||
        title.contains('sunscreen') ||
        title.contains('sun screen') ||
        title.contains('spf') ||
        title.contains('پارێزەری خۆر') ||
        title.contains('واقي الشمس')) {
      return (
        'sunscreenReminderTitle',
        'sunscreenReminderBody',
        {'task': task.title},
      );
    }
    if (task.id.contains('hydration') ||
        title.contains('hydration') ||
        title.contains('water') ||
        title.contains('ئاو') ||
        title.contains('ترطيب') ||
        title.contains('الماء')) {
      return (
        'hydrationReminderTitle',
        'hydrationReminderBody',
        {'task': task.title},
      );
    }
    return (
      'dailyReminderTitle',
      'dailyReminderBody',
      {'task': task.title},
    );
  }

  timezone.TZDateTime _timeForNextWeekday(
    int weekday,
    int minutes,
  ) {
    final now = timezone.TZDateTime.now(timezone.local);
    var daysAhead = (weekday - now.weekday) % 7;
    var result = timezone.TZDateTime(
      timezone.local,
      now.year,
      now.month,
      now.day + daysAhead,
      minutes ~/ 60,
      minutes % 60,
    );
    if (!result.isAfter(now)) {
      daysAhead = daysAhead == 0 ? 7 : daysAhead;
      result = timezone.TZDateTime(
        timezone.local,
        now.year,
        now.month,
        now.day + daysAhead,
        minutes ~/ 60,
        minutes % 60,
      );
    }
    return result;
  }

  int _notificationId(String taskId, int weekday) {
    var hash = 0x811C9DC5;
    for (final byte in utf8.encode('$taskId:$weekday')) {
      hash = ((hash ^ byte) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  @override
  Future<void> cancelTask(String taskId) async {
    if (!isSupported) return;
    await initialize(_onTap ?? (_) {});
    for (var weekday = 1; weekday <= 7; weekday++) {
      await _notifications.cancel(id: _notificationId(taskId, weekday));
    }
  }

  @override
  Future<void> cancelAllRoutineTasks(Iterable<String> taskIds) async {
    final ids = taskIds.toSet();
    if (!isSupported || ids.isEmpty) return;
    await initialize(_onTap ?? (_) {});
    for (final taskId in ids) {
      await cancelTask(taskId);
    }
  }

  @override
  Future<void> previewAlert({
    required bool sound,
    required bool vibration,
    required String language,
    required String title,
    required String body,
    required void Function(String? payload) onTap,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('Notification preview is not supported here.');
    }
    await initialize(onTap);
    final granted = _permissionGranted || await requestPermission();
    if (!granted) throw const RoutineNotificationPermissionDenied();
    const id = 0x534B494E;
    await _notifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'skin_routine_preview_${sound ? 'sound' : 'silent'}_'
          '${vibration ? 'vibrate' : 'still'}',
          _text(language, 'previewChannelName'),
          channelDescription: _text(language, 'previewChannelDescription'),
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          playSound: sound,
          enableVibration: vibration,
        ),
        iOS: DarwinNotificationDetails(presentSound: sound),
      ),
    );
    if (vibration) {
      await HapticFeedback.vibrate();
    }
    unawaited(
      Future<void>.delayed(const Duration(seconds: 5))
          .then((_) => _notifications.cancel(id: id)),
    );
  }
}

class RoutineNotificationPermissionDenied implements Exception {
  const RoutineNotificationPermissionDenied();
}

class RoutineController extends ChangeNotifier {
  RoutineController({
    RoutineScheduler? scheduler,
    RoutineWidgetBridge? widgetBridge,
    SharedPreferences? preferences,
    DateTime Function()? clock,
  })  : _scheduler = scheduler ?? LocalRoutineScheduler(),
        _widgetBridge = widgetBridge,
        _preferences = preferences,
        _clock = clock ?? DateTime.now;

  static const _tasksKey = 'skin_routine_tasks_v1';
  static const _notificationsKey = 'skin_routine_notifications_v1';
  static const _notificationSettingsKey = 'skin_notification_settings_v1';
  static const _widgetCustomizationKey = 'skin_widget_customization_v1';

  final RoutineScheduler _scheduler;
  final RoutineWidgetBridge? _widgetBridge;
  SharedPreferences? _preferences;
  final DateTime Function() _clock;
  final StreamController<Uri> _widgetLinkController =
      StreamController<Uri>.broadcast();
  StreamSubscription<Uri?>? _widgetClickSubscription;
  Uri? _pendingWidgetLink;
  List<RoutineTask> _tasks = [];
  List<RoutineNotification> _notifications = [];
  RoutineNotificationSettings _notificationSettings =
      const RoutineNotificationSettings();
  WidgetCustomization _widgetCustomization = const WidgetCustomization();
  String _widgetLanguage = 'en';

  List<RoutineTask> get tasks => List.unmodifiable(_tasks);
  List<RoutineNotification> get notifications =>
      List.unmodifiable(_notifications);
  RoutineNotificationSettings get notificationSettings => _notificationSettings;
  bool get supportsNotifications => _scheduler.isSupported;
  Future<bool> get notificationPermissionGranted => _scheduler.hasPermission();

  Future<void> requestNotificationPermission() async {
    if (!_scheduler.isSupported) {
      throw UnsupportedError('Routine notifications are not supported here.');
    }
    if (!await _scheduler.requestPermission()) {
      throw const RoutineNotificationPermissionDenied();
    }
  }

  WidgetCustomization get widgetCustomization => _widgetCustomization;
  Stream<Uri> get widgetLinks => _widgetLinkController.stream;
  Uri? get pendingWidgetLink => _pendingWidgetLink;
  bool get supportsWidgetPinning =>
      _widgetBridge?.isSupported == true &&
      defaultTargetPlatform == TargetPlatform.android;

  Future<bool> requestPinWidget() async {
    final bridge = _widgetBridge;
    if (bridge == null || !bridge.isSupported) return false;
    return bridge.requestPinWidget();
  }

  Uri? takePendingWidgetLink() {
    final link = _pendingWidgetLink;
    _pendingWidgetLink = null;
    return link;
  }

  Future<void> init({SharedPreferences? preferences}) async {
    _preferences = preferences ?? await SharedPreferences.getInstance();
    _tasks = _readList<RoutineTask>(
      _tasksKey,
      RoutineTask.fromJson,
      _defaultTasks,
    );
    _notifications = _readList<RoutineNotification>(
      _notificationsKey,
      RoutineNotification.fromJson,
      () => const [],
    );
    _notificationSettings = _readObject(
      _notificationSettingsKey,
      RoutineNotificationSettings.fromJson,
      const RoutineNotificationSettings(),
    );
    _widgetCustomization = _readObject(
      _widgetCustomizationKey,
      WidgetCustomization.fromJson,
      const WidgetCustomization(),
    );
    final bridge = _widgetBridge;
    if (bridge != null && bridge.isSupported) {
      try {
        _widgetClickSubscription ??= bridge.clicks.listen(
          _onWidgetUri,
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('Home screen widget click stream failed: $error');
          },
        );
        unawaited(
          bridge.initialLaunch().then(
            _onWidgetUri,
            onError: (Object error, StackTrace stackTrace) {
              debugPrint('Could not read home widget launch link: $error');
            },
          ),
        );
      } on MissingPluginException catch (error) {
        debugPrint('Home screen widget bridge unavailable: $error');
      }
    }
    await rescheduleEnabledTasks();
    await syncWidgetData();
    notifyListeners();
  }

  List<T> _readList<T>(
    String key,
    T Function(Map<String, dynamic>) decode,
    List<T> Function() fallback,
  ) {
    final raw = _preferences?.getString(key);
    if (raw == null) return fallback();
    try {
      return (jsonDecode(raw) as List)
          .map((item) => decode(item as Map<String, dynamic>))
          .toList();
    } on Object catch (error, stackTrace) {
      debugPrint(
          'Invalid persisted routine data for $key: $error\n$stackTrace');
      return fallback();
    }
  }

  T _readObject<T>(
    String key,
    T Function(Map<String, dynamic>) decode,
    T fallback,
  ) {
    final raw = _preferences?.getString(key);
    if (raw == null) return fallback;
    try {
      return decode(jsonDecode(raw) as Map<String, dynamic>);
    } on Object catch (error, stackTrace) {
      debugPrint(
          'Invalid persisted routine data for $key: $error\n$stackTrace');
      return fallback;
    }
  }

  static List<RoutineTask> _defaultTasks() => [
        _task('morning-cleanser', 'Cleanse', RoutinePeriod.morning, 7 * 60),
        _task('morning-moisturizer', 'Moisturize', RoutinePeriod.morning,
            7 * 60 + 5),
        _task('morning-sunscreen', 'Apply sunscreen', RoutinePeriod.morning,
            8 * 60),
        _task('afternoon-hydration', 'Hydration break', RoutinePeriod.afternoon,
            13 * 60),
        _task('evening-cleanser', 'Cleanse', RoutinePeriod.evening, 20 * 60),
        _task('evening-moisturizer', 'Moisturize', RoutinePeriod.evening,
            20 * 60 + 10),
      ];

  static RoutineTask _task(
    String id,
    String name,
    RoutinePeriod period,
    int minutes,
  ) =>
      RoutineTask(
        id: id,
        title: name,
        period: period,
        weekdays: const [1, 2, 3, 4, 5, 6, 7],
        reminderMinutes: minutes,
        reminderEnabled: false,
      );

  static const RoutineTask _weeklySummaryTask = RoutineTask(
    id: 'weekly-summary',
    title: 'Your weekly skincare routine summary',
    period: RoutinePeriod.evening,
    weekdays: [DateTime.sunday],
    reminderMinutes: 18 * 60,
    reminderEnabled: true,
  );

  static const RoutineTask _aiScanReminderTask = RoutineTask(
    id: 'ai-scan-reminder',
    title: 'A gentle reminder for your skin check-in',
    period: RoutinePeriod.evening,
    weekdays: [1, 2, 3, 4, 5, 6, 7],
    reminderMinutes: 19 * 60,
    reminderEnabled: true,
  );

  Future<void> addTask({
    required String title,
    required RoutinePeriod period,
    required List<int> weekdays,
    required int reminderMinutes,
    bool reminderEnabled = false,
  }) async {
    final normalized = title.trim();
    if (normalized.isEmpty) throw ArgumentError.value(title, 'title');
    if (weekdays.isEmpty ||
        weekdays.any((weekday) => weekday < 1 || weekday > 7)) {
      throw ArgumentError.value(weekdays, 'weekdays');
    }
    if (reminderMinutes < 0 || reminderMinutes >= 24 * 60) {
      throw ArgumentError.value(reminderMinutes, 'reminderMinutes');
    }
    final task = RoutineTask(
      id: '${_clock().microsecondsSinceEpoch}-${_tasks.length}',
      title: normalized,
      period: period,
      weekdays: weekdays.toSet().toList()..sort(),
      reminderMinutes: reminderMinutes,
      reminderEnabled: reminderEnabled,
    );
    _tasks = [..._tasks, task];
    await _persistTasks();
    if (reminderEnabled && _notificationSettings.masterEnabled) {
      await _scheduler.schedule(
        task,
        _notificationSettings,
        language: _widgetLanguage,
        onTap: _onNotificationTap,
      );
    }
    await syncWidgetData();
    notifyListeners();
  }

  Future<void> updateTask(RoutineTask updated) async {
    final index = _tasks.indexWhere((task) => task.id == updated.id);
    if (index < 0) return;
    if (updated.title.trim().isEmpty ||
        updated.weekdays.isEmpty ||
        updated.weekdays.any((weekday) => weekday < 1 || weekday > 7) ||
        updated.reminderMinutes < 0 ||
        updated.reminderMinutes >= 24 * 60) {
      throw ArgumentError.value(updated, 'updated');
    }
    final previous = _tasks[index];
    final task = updated.copyWith(
      title: updated.title.trim(),
      weekdays: updated.weekdays.toSet().toList()..sort(),
    );
    _tasks = [..._tasks]..[index] = task;
    await _persistTasks();
    if (previous.reminderEnabled && _notificationSettings.masterEnabled) {
      await _scheduler.cancelTask(task.id);
    }
    if (task.reminderEnabled && _notificationSettings.masterEnabled) {
      await _scheduler.schedule(
        task,
        _notificationSettings,
        language: _widgetLanguage,
        onTap: _onNotificationTap,
      );
    }
    await syncWidgetData();
    notifyListeners();
  }

  Future<void> deleteTask(String id) async {
    final hadReminder = _tasks.any(
      (item) => item.id == id && item.reminderEnabled,
    );
    _tasks = _tasks.where((task) => task.id != id).toList();
    await _persistTasks();
    if (hadReminder && _notificationSettings.masterEnabled) {
      await _scheduler.cancelTask(id);
    }
    await syncWidgetData();
    notifyListeners();
  }

  Future<void> toggleCompletion(String id, DateTime day) async {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    final task = _tasks[index];
    final key = RoutineTask.dayKey(day);
    final completed = {...task.completedDays};
    final wasCompleted = completed.remove(key);
    if (!wasCompleted) completed.add(key);
    _tasks = [..._tasks]..[index] = task.copyWith(completedDays: completed);
    await _persistTasks();
    if (!wasCompleted) {
      await addNotification(
        title: 'Routine task completed',
        body: task.title,
        category: 'routine',
        deepLink: 'skinai://routine/daily',
      );
    }
    await syncWidgetData();
    notifyListeners();
  }

  Future<void> copyDayRoutine(DateTime source, DateTime destination) async {
    final sourceTasks = tasksForDay(source);
    for (final sourceTask in sourceTasks) {
      final match = _tasks.indexWhere(
        (task) =>
            task.title == sourceTask.title && task.period == sourceTask.period,
      );
      if (match >= 0) {
        final task = _tasks[match];
        final days = {...task.weekdays, destination.weekday}.toList()..sort();
        _tasks[match] = task.copyWith(weekdays: days);
      } else {
        _tasks.add(
          RoutineTask(
            id: '${_clock().microsecondsSinceEpoch}-${_tasks.length}',
            title: sourceTask.title,
            period: sourceTask.period,
            weekdays: [destination.weekday],
            reminderMinutes: sourceTask.reminderMinutes,
            reminderEnabled: false,
          ),
        );
      }
    }
    await _persistTasks();
    await rescheduleEnabledTasks();
    await syncWidgetData();
    notifyListeners();
  }

  Future<void> resetWeek({DateTime? weekOf}) async {
    final now = weekOf ?? _clock();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final keys = {
      for (var day = 0; day < 7; day++)
        RoutineTask.dayKey(start.add(Duration(days: day))),
    };
    _tasks = [
      for (final task in _tasks)
        task.copyWith(
          completedDays: task.completedDays.difference(keys),
        ),
    ];
    await _persistTasks();
    await syncWidgetData();
    notifyListeners();
  }

  List<RoutineTask> tasksForDay(DateTime day, {RoutinePeriod? period}) => _tasks
      .where(
        (task) =>
            task.appliesTo(day) && (period == null || task.period == period),
      )
      .toList();

  int completedCount(DateTime day) =>
      tasksForDay(day).where((task) => task.isCompletedOn(day)).length;

  int taskCount(DateTime day) => tasksForDay(day).length;

  double dailyProgress(DateTime day) {
    final total = taskCount(day);
    return total == 0 ? 0 : completedCount(day) / total;
  }

  int completedCountForWeek(DateTime weekStart) {
    var total = 0;
    for (var offset = 0; offset < 7; offset++) {
      total += completedCount(weekStart.add(Duration(days: offset)));
    }
    return total;
  }

  int taskCountForWeek(DateTime weekStart) {
    var total = 0;
    for (var offset = 0; offset < 7; offset++) {
      total += taskCount(weekStart.add(Duration(days: offset)));
    }
    return total;
  }

  int get currentStreak {
    var streak = 0;
    final today = DateTime(_clock().year, _clock().month, _clock().day);
    for (var offset = 0; offset < 365; offset++) {
      final day = today.subtract(Duration(days: offset));
      if (taskCount(day) == 0 || dailyProgress(day) < 1) break;
      streak++;
    }
    return streak;
  }

  Future<void> updateNotificationSettings(
    RoutineNotificationSettings settings,
  ) async {
    _notificationSettings = settings;
    await _preferences?.setString(
      _notificationSettingsKey,
      jsonEncode(settings.toJson()),
    );
    if (!settings.masterEnabled) {
      await _scheduler.cancelAllRoutineTasks(
        [
          ..._tasks
              .where((task) => task.reminderEnabled)
              .map((task) => task.id),
          _weeklySummaryTask.id,
          _aiScanReminderTask.id,
        ],
      );
    } else {
      await rescheduleEnabledTasks();
    }
    await syncWidgetData();
    notifyListeners();
  }

  Future<void> rescheduleEnabledTasks() async {
    if (!_scheduler.isSupported) return;
    if (_notificationSettings.masterEnabled) {
      if (_tasks.any((task) => task.reminderEnabled) ||
          _notificationSettings.weeklySummaryEnabled ||
          _notificationSettings.aiScanEnabled) {
        await _scheduler.initialize(_onNotificationTap);
      }
      for (final task in _tasks) {
        if (task.reminderEnabled) {
          await _scheduler.schedule(
            task,
            _notificationSettings,
            language: _widgetLanguage,
            onTap: _onNotificationTap,
          );
        }
      }
      if (_notificationSettings.weeklySummaryEnabled) {
        await _scheduler.schedule(
          _weeklySummaryTask,
          _notificationSettings,
          language: _widgetLanguage,
          onTap: _onNotificationTap,
        );
      } else {
        await _scheduler.cancelTask(_weeklySummaryTask.id);
      }
      if (_notificationSettings.aiScanEnabled) {
        await _scheduler.schedule(
          _aiScanReminderTask,
          _notificationSettings,
          language: _widgetLanguage,
          onTap: _onNotificationTap,
        );
      } else {
        await _scheduler.cancelTask(_aiScanReminderTask.id);
      }
    }
  }

  Future<void> previewAlert({
    required String title,
    required String body,
  }) =>
      _scheduler.previewAlert(
        sound: _notificationSettings.soundEnabled,
        vibration: _notificationSettings.vibrationEnabled,
        language: _widgetLanguage,
        title: title,
        body: body,
        onTap: _onNotificationTap,
      );

  Future<void> addNotification({
    required String title,
    required String body,
    required String category,
    String? type,
    String? titleKey,
    String? bodyKey,
    Map<String, String> parameters = const {},
    String? deepLink,
    bool important = false,
  }) async {
    final notificationType = type ?? category;
    if (!_notificationCategoryEnabled(notificationType)) return;
    final translationKeys = _notificationKeys(notificationType);
    final private = _notificationSettings.privatePreview;
    final idPrefix = '${_clock().microsecondsSinceEpoch}';
    var id = idPrefix;
    var suffix = 1;
    while (_notifications.any((item) => item.id == id)) {
      id = '$idPrefix-$suffix';
      suffix++;
    }
    final notification = RoutineNotification(
      id: id,
      title: private ? 'SkinAI update' : title,
      body: private ? 'Open SkinAI to view your update.' : body,
      category: category,
      createdAt: _clock(),
      read: false,
      deepLink: deepLink,
      important: important,
      type: notificationType,
      titleKey: private ? 'privateTitle' : titleKey ?? translationKeys.$1,
      bodyKey: private ? 'privateBody' : bodyKey ?? translationKeys.$2,
      parameters: {
        ...parameters,
        if (parameters['task'] == null &&
            (notificationType == 'routine' ||
                notificationType == 'routine_task_completed' ||
                notificationType == 'reminder' ||
                notificationType == 'daily_reminder' ||
                notificationType == 'sunscreen_reminder' ||
                notificationType == 'hydration_reminder'))
          'task': body,
      },
    );
    _notifications = [notification, ..._notifications].take(200).toList();
    await _persistNotifications();
    notifyListeners();
  }

  bool _notificationCategoryEnabled(String type) => switch (type) {
        'daily_reminder' || 'reminder' => _notificationSettings.dailyEnabled,
        'sunscreen_reminder' => _notificationSettings.sunscreenEnabled,
        'hydration_reminder' => _notificationSettings.hydrationEnabled,
        'scan_checkin' => _notificationSettings.aiScanEnabled,
        'weekly_summary' => _notificationSettings.weeklySummaryEnabled,
        'doctor_reply' ||
        'message' =>
          _notificationSettings.doctorMessagesEnabled,
        'appointment_reminder' ||
        'appointment' =>
          _notificationSettings.appointmentRemindersEnabled,
        'subscription_expiration' ||
        'subscription' =>
          _notificationSettings.subscriptionAlertsEnabled,
        'system_update' ||
        'update' =>
          _notificationSettings.systemUpdatesEnabled,
        'security_alert' ||
        'security' =>
          _notificationSettings.securityAlertsEnabled,
        _ => true,
      };

  (String?, String?) _notificationKeys(String type) => switch (type) {
        'routine' || 'routine_task_completed' => (
            'routineTaskCompletedTitle',
            'routineTaskCompletedBody'
          ),
        'reminder' || 'daily_reminder' => (
            'dailyReminderTitle',
            'dailyReminderBody'
          ),
        'sunscreen_reminder' => (
            'sunscreenReminderTitle',
            'sunscreenReminderBody'
          ),
        'hydration_reminder' => (
            'hydrationReminderTitle',
            'hydrationReminderBody'
          ),
        'weekly_summary' => ('weeklySummaryTitle', 'weeklySummaryBody'),
        'scan' || 'scan_result_available' => (
            'scanResultTitle',
            'scanResultBody'
          ),
        'scan_checkin' => ('scanCheckinTitle', 'scanCheckinBody'),
        'message' || 'doctor_reply' => ('doctorReplyTitle', 'doctorReplyBody'),
        'appointment' || 'appointment_reminder' => (
            'appointmentReminderTitle',
            'appointmentReminderBody'
          ),
        'subscription' || 'subscription_expiration' => (
            'subscriptionExpirationTitle',
            'subscriptionExpirationBody'
          ),
        'security' || 'security_alert' => (
            'securityAlertTitle',
            'securityAlertBody'
          ),
        'update' || 'system_update' => ('appUpdateTitle', 'appUpdateBody'),
        _ => (null, null),
      };

  Future<void> markRead(String id) async {
    _notifications = [
      for (final notification in _notifications)
        if (notification.id == id)
          notification.copyWith(read: true)
        else
          notification,
    ];
    await _persistNotifications();
    notifyListeners();
  }

  Future<void> markAllRead() async {
    _notifications = [
      for (final notification in _notifications)
        notification.copyWith(read: true),
    ];
    await _persistNotifications();
    notifyListeners();
  }

  Future<RoutineNotification?> deleteNotification(String id) async {
    final removed = _notifications.where((item) => item.id == id).firstOrNull;
    if (removed == null) return null;
    _notifications =
        _notifications.where((notification) => notification.id != id).toList();
    await _persistNotifications();
    notifyListeners();
    return removed;
  }

  Future<List<RoutineNotification>> clearNotifications() async {
    final removed = List<RoutineNotification>.unmodifiable(_notifications);
    if (removed.isEmpty) return removed;
    _notifications = [];
    await _persistNotifications();
    notifyListeners();
    return removed;
  }

  Future<void> restoreNotifications(
    Iterable<RoutineNotification> notifications,
  ) async {
    final existingIds = _notifications.map((item) => item.id).toSet();
    _notifications = [
      ..._notifications,
      ...notifications.where((item) => !existingIds.contains(item.id)),
    ]..sort((first, second) => second.createdAt.compareTo(first.createdAt));
    _notifications = _notifications.take(200).toList();
    await _persistNotifications();
    notifyListeners();
  }

  void _onNotificationTap(String? payload) {
    if (payload == null) return;
    final uri = Uri.tryParse(payload);
    if (uri == null) return;
    final taskId = uri.host;
    RoutineTask? task;
    for (final item in _tasks) {
      if (item.id == taskId) {
        task = item;
        break;
      }
    }
    if (task != null) {
      unawaited(
        addNotification(
          title: 'Routine reminder',
          body: task.title,
          category: 'reminder',
          deepLink: 'skinai://routine/daily',
        ),
      );
    } else if (taskId == _weeklySummaryTask.id) {
      unawaited(
        addNotification(
          title: 'Weekly skincare summary',
          body: 'Review your skincare routine progress for the week.',
          category: 'update',
          type: 'weekly_summary',
          deepLink: 'skinai://routine/weekly',
        ),
      );
      _onWidgetUri(Uri.parse('skinai://routine/weekly'));
      return;
    } else if (taskId == _aiScanReminderTask.id) {
      unawaited(
        addNotification(
          title: 'Skin check-in reminder',
          body: 'Open the scanner for your skin check-in.',
          category: 'scan',
          type: 'scan_checkin',
          deepLink: 'skinai://scanner',
        ),
      );
      _onWidgetUri(Uri.parse('skinai://scanner'));
      return;
    }
    _onWidgetUri(Uri.parse('skinai://routine/daily'));
  }

  void _onWidgetUri(Uri? uri) {
    if (uri == null) return;
    _pendingWidgetLink = uri;
    _widgetLinkController.add(uri);
  }

  Future<void> saveWidgetCustomization(
      WidgetCustomization customization) async {
    _widgetCustomization = customization;
    await _preferences?.setString(
      _widgetCustomizationKey,
      jsonEncode(customization.toJson()),
    );
    await syncWidgetData();
    notifyListeners();
  }

  Future<void> setWidgetLanguage(String language) async {
    if (_widgetLanguage == language) return;
    _widgetLanguage = language;
    await rescheduleEnabledTasks();
    await syncWidgetData();
  }

  Future<void> syncWidgetData() async {
    final bridge = _widgetBridge;
    if (bridge == null) return;
    final today = DateTime(_clock().year, _clock().month, _clock().day);
    final todaysTasks = tasksForDay(today);
    final incomplete = todaysTasks
        .where((task) => !task.isCompletedOn(today))
        .toList()
      ..sort((first, second) =>
          first.reminderMinutes.compareTo(second.reminderMinutes));
    final completedThisWeek = completedCountForWeek(weekStart(today));
    final totalThisWeek = taskCountForWeek(weekStart(today));
    await bridge.update({
      'style': _widgetCustomization.style,
      'accentColor': _widgetCustomization.accentColor,
      'theme': _widgetCustomization.theme,
      'compact': _widgetCustomization.compact,
      'showProgress': _widgetCustomization.showProgress,
      'showTasks': _widgetCustomization.showTasks,
      'dataPeriod': _widgetCustomization.dataPeriod,
      'completedToday': completedCount(today),
      'totalToday': todaysTasks.length,
      'progressToday': (dailyProgress(today) * 100).round(),
      'nextTask': incomplete.isEmpty
          ? ''
          : _notificationSettings.privatePreview
              ? 'Skincare routine'
              : incomplete.first.title,
      'nextTaskMinutes':
          incomplete.isEmpty ? -1 : incomplete.first.reminderMinutes,
      'weeklyCompleted': completedThisWeek,
      'weeklyTotal': totalThisWeek,
      'weeklyProgress': totalThisWeek == 0
          ? 0
          : (completedThisWeek / totalThisWeek * 100).round(),
      'weeklyDailyProgress': List<int>.generate(
        7,
        (index) =>
            (dailyProgress(weekStart(today).add(Duration(days: index))) * 100)
                .round(),
      ),
      'streak': currentStreak,
      'consistency': consistencyPercent(7),
      'today': RoutineTask.dayKey(today),
      'tasks': jsonEncode(todaysTasks
          .take(4)
          .map((task) => {
                'title': _notificationSettings.privatePreview
                    ? 'Skincare task'
                    : task.title,
                'completed': task.isCompletedOn(today),
              })
          .toList()),
      'labels': _widgetLabels,
    });
  }

  Map<String, String> get _widgetLabels {
    switch (_widgetLanguage) {
      case 'ku':
      case 'badini':
        return const {
          'brand': 'SkinAI',
          'today': 'ئەمڕۆ',
          'dailyProgress': 'پێشکەوتنی ڕۆژانە',
          'morning': 'ڕۆتینی بەیانی',
          'evening': 'ڕۆتینی ئێوارە',
          'weekly': 'هەفتانە',
          'minimal': 'پێشکەوتنی سادە',
          'statistics': 'ئاماری بەردەوامی',
          'quickActions': 'کردارە خێراکان',
          'complete': 'تەواو',
          'dailyAction': 'ڕۆژانە',
          'weeklyAction': 'هەفتانە',
          'scanAction': 'پشکنین',
          'consistency': 'بەردەوامی',
          'dayStreak': 'ڕۆژ بەردەوام',
          'reminder': 'بیرخەرەوە',
          'noTask': 'ئەمڕۆ ئەرک نییە',
          'eveningHint': 'چەند هەنگاوێکی ئارام بۆ ئەمشەو',
        };
      case 'ar':
        return const {
          'brand': 'SkinAI',
          'today': 'اليوم',
          'dailyProgress': 'التقدم اليومي',
          'morning': 'روتين الصباح',
          'evening': 'روتين المساء',
          'weekly': 'أسبوعي',
          'minimal': 'تقدم بسيط',
          'statistics': 'إحصاءات الالتزام',
          'quickActions': 'إجراءات سريعة',
          'complete': 'مكتمل',
          'dailyAction': 'يومي',
          'weeklyAction': 'أسبوعي',
          'scanAction': 'فحص',
          'consistency': 'الاستمرارية',
          'dayStreak': 'أيام متتالية',
          'reminder': 'تذكير',
          'noTask': 'لا مهام اليوم',
          'eveningHint': 'خطوات هادئة لهذا المساء',
        };
      default:
        return const {
          'brand': 'SkinAI',
          'today': 'Today',
          'dailyProgress': "Today's progress",
          'morning': 'Morning routine',
          'evening': 'Evening routine',
          'weekly': 'Your week',
          'minimal': 'Minimal progress',
          'statistics': 'Streak statistics',
          'quickActions': 'Quick actions',
          'complete': 'complete',
          'dailyAction': 'Daily',
          'weeklyAction': 'Weekly',
          'scanAction': 'Scan',
          'consistency': 'consistency',
          'dayStreak': 'day streak',
          'reminder': 'Reminder',
          'noTask': 'No tasks today',
          'eveningHint': 'A few calm steps for tonight',
        };
    }
  }

  Future<void> _persistTasks() async {
    await _preferences?.setString(
      _tasksKey,
      jsonEncode(_tasks.map((task) => task.toJson()).toList()),
    );
  }

  Future<void> _persistNotifications() async {
    await _preferences?.setString(
      _notificationsKey,
      jsonEncode(_notifications.map((item) => item.toJson()).toList()),
    );
  }

  @override
  void dispose() {
    _widgetClickSubscription?.cancel();
    _widgetLinkController.close();
    super.dispose();
  }

  int completedInLastDays(int days) {
    final now = _clock();
    var count = 0;
    for (var offset = 0; offset < days; offset++) {
      count += completedCount(now.subtract(Duration(days: offset)));
    }
    return count;
  }

  int consistencyPercent(int days) {
    final now = _clock();
    var completed = 0;
    var total = 0;
    for (var offset = 0; offset < days; offset++) {
      final day = now.subtract(Duration(days: offset));
      completed += completedCount(day);
      total += taskCount(day);
    }
    if (total == 0) return 0;
    return (completed / total * 100).round();
  }

  int get unseenNotificationCount =>
      _notifications.where((item) => !item.read).length;

  static DateTime weekStart(DateTime date) =>
      DateTime(date.year, date.month, date.day)
          .subtract(Duration(days: date.weekday - 1));
}
