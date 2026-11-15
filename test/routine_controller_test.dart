import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skin_ai/localization/app_localizations.dart';
import 'package:skin_ai/routines/home_widget_bridge.dart';
import 'package:skin_ai/routines/routine_controller.dart';
import 'package:skin_ai/routines/routine_models.dart';
import 'package:skin_ai/routines/routine_screens.dart';
import 'package:skin_ai/notifications/notification_screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;
  final monday = DateTime(2025, 1, 6);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  test('persists task edits and completion state across controller reloads',
      () async {
    final controller = RoutineController(
      scheduler: _FakeScheduler(),
      clock: () => monday,
    );
    await controller.init(preferences: preferences);
    await controller.addTask(
      title: 'Apply moisturizer',
      period: RoutinePeriod.morning,
      weekdays: const [1, 3, 5],
      reminderMinutes: 7 * 60 + 15,
    );
    final taskId = controller.tasks.last.id;
    await controller.toggleCompletion(taskId, monday);

    final restored = RoutineController(
      scheduler: _FakeScheduler(),
      clock: () => monday,
    );
    await restored.init(preferences: preferences);

    final task = restored.tasks.singleWhere((item) => item.id == taskId);
    expect(task.title, 'Apply moisturizer');
    expect(task.weekdays, [1, 3, 5]);
    expect(task.reminderMinutes, 435);
    expect(task.isCompletedOn(monday), isTrue);
    expect(restored.dailyProgress(monday), lessThan(1));
  });

  test('removing a task removes it from storage and statistics', () async {
    final controller = RoutineController(scheduler: _FakeScheduler());
    await controller.init(preferences: preferences);
    final task = controller.tasks.first;
    await controller.deleteTask(task.id);

    expect(controller.tasks.any((item) => item.id == task.id), isFalse);
    expect(controller.taskCount(DateTime.now()), controller.tasks.length);

    final restored = RoutineController(scheduler: _FakeScheduler());
    await restored.init(preferences: preferences);
    expect(restored.tasks.any((item) => item.id == task.id), isFalse);
  });

  test('persists notification settings and keeps history private by default',
      () async {
    final controller = RoutineController(scheduler: _FakeScheduler());
    await controller.init(preferences: preferences);
    await controller.updateNotificationSettings(
      controller.notificationSettings.copyWith(
        quietHoursEnabled: true,
        quietStartMinutes: 21 * 60,
        quietEndMinutes: 6 * 60 + 30,
        vibrationEnabled: false,
      ),
    );
    await controller.addNotification(
      title: 'Moisturizer reminder',
      body: 'Apply your moisturizer',
      category: 'reminder',
    );

    final restored = RoutineController(scheduler: _FakeScheduler());
    await restored.init(preferences: preferences);

    expect(restored.notificationSettings.quietHoursEnabled, isTrue);
    expect(restored.notificationSettings.quietStartMinutes, 1260);
    expect(restored.notificationSettings.quietEndMinutes, 390);
    expect(restored.notificationSettings.vibrationEnabled, isFalse);
    expect(restored.notifications.single.title, 'SkinAI update');
    expect(
        restored.notifications.single.body, 'Open SkinAI to view your update.');
    expect(restored.notifications.single.titleKey, 'privateTitle');
    expect(restored.notifications.single.bodyKey, 'privateBody');
    expect(restored.unseenNotificationCount, 1);
    await restored.markAllRead();
    expect(restored.unseenNotificationCount, 0);
  });

  test('stores notification type and translated keys with legacy text support',
      () async {
    final controller = RoutineController(scheduler: _FakeScheduler());
    await controller.init(preferences: preferences);
    await controller.updateNotificationSettings(
      controller.notificationSettings.copyWith(privatePreview: false),
    );
    await controller.addNotification(
      title: 'New message',
      body: 'Open to read',
      category: 'message',
      type: 'doctor_reply',
      titleKey: 'doctorReplyTitle',
      bodyKey: 'doctorReplyBody',
      important: true,
    );

    final stored = controller.notifications.single;
    expect(stored.type, 'doctor_reply');
    expect(stored.titleKey, 'doctorReplyTitle');
    expect(stored.bodyKey, 'doctorReplyBody');
    expect(stored.important, isTrue);

    final restored = RoutineController(scheduler: _FakeScheduler());
    await restored.init(preferences: preferences);
    expect(restored.notifications.single.type, 'doctor_reply');
    expect(restored.notifications.single.titleKey, 'doctorReplyTitle');

    final legacy = RoutineNotification.fromJson({
      'id': 'legacy',
      'title': 'Saved title',
      'body': 'Saved body',
      'createdAt': monday.toIso8601String(),
      'read': false,
    });
    expect(legacy.title, 'Saved title');
    expect(legacy.body, 'Saved body');
    expect(legacy.titleKey, isNull);
  });

  test(
      'deleting notification can be undone and settings persist all categories',
      () async {
    final controller = RoutineController(scheduler: _FakeScheduler());
    await controller.init(preferences: preferences);
    await controller.updateNotificationSettings(
      controller.notificationSettings.copyWith(
        doctorMessagesEnabled: false,
        appointmentRemindersEnabled: false,
        subscriptionAlertsEnabled: false,
        systemUpdatesEnabled: false,
        securityAlertsEnabled: false,
      ),
    );
    await controller.addNotification(
      title: 'Update',
      body: 'Details',
      category: 'reminder',
    );

    final removed = await controller.deleteNotification(
      controller.notifications.single.id,
    );
    expect(removed, isNotNull);
    expect(controller.notifications, isEmpty);
    await controller.restoreNotifications([removed!]);
    expect(controller.notifications, hasLength(1));

    final restored = RoutineController(scheduler: _FakeScheduler());
    await restored.init(preferences: preferences);
    expect(restored.notificationSettings.doctorMessagesEnabled, isFalse);
    expect(restored.notificationSettings.appointmentRemindersEnabled, isFalse);
    expect(restored.notificationSettings.subscriptionAlertsEnabled, isFalse);
    expect(restored.notificationSettings.systemUpdatesEnabled, isFalse);
    expect(restored.notificationSettings.securityAlertsEnabled, isFalse);
    expect(restored.notifications, hasLength(1));
  });

  test('disabled notification categories do not create new center entries',
      () async {
    final controller = RoutineController(scheduler: _FakeScheduler());
    await controller.init(preferences: preferences);
    await controller.updateNotificationSettings(
      controller.notificationSettings.copyWith(
        doctorMessagesEnabled: false,
        weeklySummaryEnabled: false,
      ),
    );

    await controller.addNotification(
      title: 'New message',
      body: 'Open to read',
      category: 'message',
      type: 'doctor_reply',
    );
    await controller.addNotification(
      title: 'Weekly summary',
      body: 'Review progress',
      category: 'update',
      type: 'weekly_summary',
    );

    expect(controller.notifications, isEmpty);
  });

  test('weekly summary and AI scan preferences schedule and cancel reminders',
      () async {
    final scheduler = _FakeScheduler();
    final controller = RoutineController(scheduler: scheduler);
    await controller.init(preferences: preferences);

    await controller.updateNotificationSettings(
      controller.notificationSettings.copyWith(
        masterEnabled: true,
        dailyEnabled: false,
        weeklySummaryEnabled: true,
        aiScanEnabled: true,
      ),
    );

    expect(
      scheduler.scheduledTasks.map((task) => task.id),
      containsAll(['weekly-summary', 'ai-scan-reminder']),
    );

    await controller.updateNotificationSettings(
      controller.notificationSettings.copyWith(masterEnabled: false),
    );
    expect(
      scheduler.cancelledTaskGroups.last,
      containsAll(['weekly-summary', 'ai-scan-reminder']),
    );

    await controller.updateNotificationSettings(
      controller.notificationSettings.copyWith(masterEnabled: true),
    );
    await controller.updateNotificationSettings(
      controller.notificationSettings.copyWith(
        weeklySummaryEnabled: false,
        aiScanEnabled: false,
      ),
    );

    expect(
      scheduler.cancelledTaskIds.sublist(
        scheduler.cancelledTaskIds.length - 2,
      ),
      ['weekly-summary', 'ai-scan-reminder'],
    );
  });

  test('routine reminders reschedule using the newly selected locale',
      () async {
    final scheduler = _FakeScheduler();
    final controller = RoutineController(scheduler: scheduler);
    await controller.init(preferences: preferences);
    await controller.setWidgetLanguage('ku');
    await controller.updateNotificationSettings(
      controller.notificationSettings.copyWith(masterEnabled: true),
    );
    await controller.addTask(
      title: 'Apply sunscreen',
      period: RoutinePeriod.morning,
      weekdays: const [1, 2, 3, 4, 5, 6, 7],
      reminderMinutes: 8 * 60,
      reminderEnabled: true,
    );
    expect(scheduler.scheduledLanguages.last, 'ku');

    await controller.setWidgetLanguage('ar');
    expect(scheduler.scheduledLanguages.last, 'ar');
  });

  test('disabled notifications do not initialize the platform scheduler',
      () async {
    final scheduler = _FakeScheduler();
    final controller = RoutineController(scheduler: scheduler);
    await controller.init(preferences: preferences);

    expect(scheduler.initializeCalls, 0);
    expect(scheduler.scheduledTasks, isEmpty);
  });

  test('widget snapshots follow saved style and hide routine task details',
      () async {
    final bridge = _FakeWidgetBridge();
    final controller = RoutineController(
      scheduler: _FakeScheduler(),
      widgetBridge: bridge,
      clock: () => monday,
    );
    await controller.init(preferences: preferences);
    await controller.setWidgetLanguage('ku');
    await controller.saveWidgetCustomization(
      controller.widgetCustomization.copyWith(
        style: 'weeklyRoutine',
        compact: true,
        dataPeriod: 'weekly',
      ),
    );

    expect(bridge.latestSnapshot?['style'], 'weeklyRoutine');
    expect(bridge.latestSnapshot?['compact'], isTrue);
    expect(bridge.latestSnapshot?['dataPeriod'], 'weekly');
    expect(bridge.latestSnapshot?['labels'], containsPair('today', 'ئەمڕۆ'));
    expect(bridge.latestSnapshot?['nextTask'], 'Skincare routine');
    expect(
      bridge.latestSnapshot?['tasks'].toString(),
      isNot(contains('Cleanse')),
    );
  });

  test('Android widget bridge resolves provider by qualified class name',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final calls = <MethodCall>[];
    const channel = MethodChannel('home_widget');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await HomeWidgetBridge().update(const {'progressToday': 50});

    final updateCall = calls.singleWhere(
      (call) => call.method == 'updateWidget',
    );
    final arguments = updateCall.arguments as Map<dynamic, dynamic>;
    expect(arguments['android'], isNull);
    expect(
      arguments['qualifiedAndroidName'],
      'com.example.flutter_application_1.SkinAIHomeWidgetProvider',
    );
  });

  test('iOS widget bridge is unavailable for sideloaded builds', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(HomeWidgetBridge().isSupported, isFalse);
  });

  testWidgets('routine completion updates progress and notification history',
      (tester) async {
    final controller = RoutineController(scheduler: _FakeScheduler());
    await controller.init(preferences: preferences);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoutineDashboardScreen(
            controller: controller,
            language: 'en',
            accentColor: const Color(0xFF168CFF),
          ),
        ),
      ),
    );
    expect(find.text("Today's progress"), findsOneWidget);
    await tester.tap(find.text('Cleanse').first);
    await tester.pump();

    expect(controller.completedCount(DateTime.now()), 1);
    expect(controller.notifications, hasLength(1));
  });

  testWidgets('expanded routine shows progress ring and period columns',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = RoutineController(scheduler: _FakeScheduler());
    await controller.init(preferences: preferences);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoutineDashboardScreen(
            controller: controller,
            language: 'en',
            accentColor: const Color(0xFF168CFF),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('routine-daily-progress')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Evening')).dx,
      greaterThan(tester.getTopLeft(find.text('Morning')).dx),
    );
    expect(find.textContaining('day streak'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small routine screen supports scaled Kurdish RTL text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = RoutineController(scheduler: _FakeScheduler());
    await controller.init(preferences: preferences);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(1.3),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: RoutineDashboardScreen(
                controller: controller,
                language: 'ku',
                accentColor: const Color(0xFF168CFF),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      Directionality.of(
        tester.element(find.byKey(const ValueKey('routine-daily-progress'))),
      ),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification center marks opened items read and filters them',
      (tester) async {
    final controller = RoutineController(scheduler: _FakeScheduler());
    await controller.init(preferences: preferences);
    await controller.addNotification(
      title: 'Routine task completed',
      body: 'Moisturize',
      category: 'routine',
      important: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationCenterScreen(
          controller: controller,
          language: 'en',
          onOpenDeepLink: (_) {},
          onMasterChanged: (_) async {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(controller.unseenNotificationCount, 1);
    await tester.tap(find.text('SkinAI update'));
    await tester.pump();
    expect(controller.unseenNotificationCount, 0);

    await tester.tap(find.text('Unread'));
    await tester.pump();
    expect(find.text('SkinAI update'), findsNothing);
    expect(
      find.text('There are no notifications in this view.'),
      findsOneWidget,
    );
  });

  testWidgets('notification center aligns filters within desktop content',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = RoutineController(scheduler: _FakeScheduler());
    await controller.init(preferences: preferences);
    await controller.addNotification(
      title: 'Routine task completed',
      body: 'Moisturize',
      category: 'routine',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationCenterScreen(
          controller: controller,
          language: 'en',
          onOpenDeepLink: (_) {},
          onMasterChanged: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getRect(
            find.byKey(const ValueKey('notification-center-content')),
          )
          .width,
      1200,
    );
    expect(
      tester.getTopLeft(find.byType(DropdownButtonFormField<String>)).dx,
      greaterThan(tester.getTopLeft(find.byType(TextField)).dx),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification settings fit small scaled RTL screens',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = RoutineController(scheduler: _FakeScheduler());
    await controller.init(preferences: preferences);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(1.3),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: NotificationSettingsScreen(
              controller: controller,
              language: 'ku',
              onMasterChanged: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      Directionality.of(
        tester.element(
          find.byKey(const ValueKey('notification-settings-content')),
        ),
      ),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification center follows live locale and RTL direction',
      (tester) async {
    final controller = RoutineController(scheduler: _FakeScheduler());
    await controller.init(preferences: preferences);
    await controller.updateNotificationSettings(
      controller.notificationSettings.copyWith(privatePreview: false),
    );
    await controller.addNotification(
      title: 'New message',
      body: 'Open to read',
      category: 'message',
      type: 'doctor_reply',
      titleKey: 'doctorReplyTitle',
      bodyKey: 'doctorReplyBody',
    );
    var locale = const Locale('en');

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Column(
            children: [
              TextButton(
                onPressed: () => setState(() => locale = const Locale('ar')),
                child: const Text('Switch language'),
              ),
              Expanded(
                child: NotificationCenterScreen(
                  controller: controller,
                  language: 'en',
                  onOpenDeepLink: (_) {},
                  onMasterChanged: (_) async {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('New message from your care team'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(NotificationCenterScreen))),
      TextDirection.ltr,
    );
    await tester.tap(find.text('Switch language'));
    await tester.pumpAndSettle();
    expect(find.text('رسالة جديدة من فريق الرعاية'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(NotificationCenterScreen))),
      TextDirection.rtl,
    );
  });

  testWidgets(
      'notification settings report denied OS permission and disable master',
      (tester) async {
    final controller = RoutineController(
      scheduler: _FakeScheduler(permissionGranted: false),
    );
    await controller.init(preferences: preferences);
    await controller.updateNotificationSettings(
      controller.notificationSettings.copyWith(masterEnabled: true),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationSettingsScreen(
          controller: controller,
          language: 'en',
          onMasterChanged: (enabled) async {
            await controller.updateNotificationSettings(
              controller.notificationSettings.copyWith(
                masterEnabled: enabled,
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'OS notification permission is off. Enable it in system settings before expecting alerts.',
      ),
      findsOneWidget,
    );
    expect(controller.notificationSettings.masterEnabled, isFalse);
  });

  testWidgets('notification quiet hours use the iOS time picker',
      (tester) async {
    final controller = RoutineController(scheduler: _FakeScheduler());
    await controller.init(preferences: preferences);
    await controller.updateNotificationSettings(
      controller.notificationSettings.copyWith(quietHoursEnabled: true),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: NotificationSettingsScreen(
          controller: controller,
          language: 'en',
          onMasterChanged: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Quiet hours start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quiet hours start'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoTimerPicker), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoTimerPicker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('widget gallery persists selected native widget style',
      (tester) async {
    final controller = RoutineController(scheduler: _FakeScheduler());
    await controller.init(preferences: preferences);

    await tester.pumpWidget(
      MaterialApp(
        home: WidgetGalleryScreen(controller: controller, language: 'en'),
      ),
    );
    final styleLabel = find.text('Evening wind-down').last;
    await tester.ensureVisible(styleLabel);
    await tester.pumpAndSettle();
    await tester.tap(styleLabel);
    await tester.pump();

    expect(controller.widgetCustomization.style, 'eveningRoutine');
  });
}

class _FakeScheduler implements RoutineScheduler {
  _FakeScheduler({this.permissionGranted = true});

  final bool permissionGranted;
  final scheduledTasks = <RoutineTask>[];
  final scheduledLanguages = <String>[];
  final cancelledTaskIds = <String>[];
  final cancelledTaskGroups = <List<String>>[];
  int initializeCalls = 0;

  @override
  bool get isSupported => true;

  @override
  Future<void> initialize(void Function(String? payload) onTap) async {
    initializeCalls++;
  }

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(
    RoutineTask task,
    RoutineNotificationSettings settings, {
    required String language,
    required void Function(String? payload) onTap,
  }) async {
    scheduledTasks.add(task);
    scheduledLanguages.add(language);
  }

  @override
  Future<void> cancelTask(String taskId) async {
    cancelledTaskIds.add(taskId);
  }

  @override
  Future<void> cancelAllRoutineTasks(Iterable<String> taskIds) async {
    cancelledTaskGroups.add(taskIds.toList());
  }

  @override
  Future<void> previewAlert({
    required bool sound,
    required bool vibration,
    required String language,
    required String title,
    required String body,
    required void Function(String? payload) onTap,
  }) async {}
}

class _FakeWidgetBridge implements RoutineWidgetBridge {
  Map<String, Object?>? latestSnapshot;

  @override
  bool get isSupported => false;

  @override
  Stream<Uri?> get clicks => const Stream<Uri?>.empty();

  @override
  Future<Uri?> initialLaunch() async => null;

  @override
  Future<bool> requestPinWidget() async => false;

  @override
  Future<void> update(Map<String, Object?> snapshot) async {
    latestSnapshot = snapshot;
  }
}
