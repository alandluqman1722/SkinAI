import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skin_ai/design/app_components.dart';
import 'package:skin_ai/local_reminder_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skin_ai/main.dart';
import 'package:skin_ai/localization/locale_helper.dart';
import 'package:skin_ai/routines/routine_controller.dart';
import 'package:skin_ai/routines/routine_models.dart';

void main() {
  testWidgets('settings tab displays the visual settings screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.text('Settings').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('SKIN & AI'), findsOneWidget);
    expect(find.text('Primary skincare goal'), findsOneWidget);
    expect(find.text('8:00 AM'), findsOneWidget);

    await tester.tap(find.text('Primary skincare goal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Acne care'), findsOneWidget);
    await tester.tap(find.text('Acne care'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(controller.skincareGoal, 'acne');
  });

  testWidgets('expanded settings uses two content columns', (tester) async {
    _setViewport(tester, const Size(1440, 1000));
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const MaterialApp(
          home: Scaffold(
            body: SettingsScreen(onLogout: _noopLogout),
          ),
        ),
      ),
    );
    await tester.pump();

    final skinSettings = tester.getTopLeft(find.text('SKIN & AI'));
    final serviceSettings = tester.getTopLeft(find.text('ABOUT & AI SERVICE'));
    expect(serviceSettings.dx, greaterThan(skinSettings.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('small Settings layout supports enlarged text', (tester) async {
    _setViewport(tester, const Size(320, 568));
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(2.0),
            ),
            child: Scaffold(
              body: SettingsScreen(onLogout: _noopLogout),
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Sensitive'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom navigation switches across all app tabs', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));

    final destinations =
        tester.widget<GlassBottomNav>(find.byType(GlassBottomNav)).items;
    expect(destinations, hasLength(5));
    expect(
      destinations.map((destination) => destination.label),
      [
        'Home',
        'History',
        'Scan',
        'Routine',
        'Settings',
      ],
    );

    for (final index in [1, 2, 3, 4, 0]) {
      await tester.tap(find.byKey(ValueKey('app-bottom-nav-$index')));
      await tester.pump();
      expect(
        tester
            .widget<GlassBottomNav>(find.byType(GlassBottomNav))
            .selectedIndex,
        index,
      );
      if (index == 3) {
        final routineSwipe = await tester.startGesture(const Offset(10, 300));
        await routineSwipe.moveTo(const Offset(130, 300));
        await routineSwipe.up();
        await tester.pump();
        expect(
          tester
              .widget<GlassBottomNav>(find.byType(GlassBottomNav))
              .selectedIndex,
          3,
        );
      }
    }

    await tester.tap(find.byKey(const ValueKey('app-bottom-nav-4')));
    await tester.pump();
    expect(find.text('SKIN & AI'), findsOneWidget);

    await tester.tap(find.text('Sensitive'));
    await tester.pump();
    expect(controller.skinType, 'sensitive');
    expect(find.text('Skin type: Sensitive'), findsOneWidget);

    await controller.setLang(AppLang.ku);
    await tester.pump();
    expect(find.text('هەستیار'), findsOneWidget);

    for (final language in [
      AppLang.ku,
      AppLang.badini,
      AppLang.ar,
      AppLang.en,
    ]) {
      await controller.setLang(language);
      await tester.pump();
      final localizedDestinations =
          tester.widget<GlassBottomNav>(find.byType(GlassBottomNav)).items;
      expect(
        localizedDestinations.map((destination) => destination.label),
        [
          controller.t('navHome'),
          controller.t('navHistory'),
          controller.t('navScan'),
          controller.t('navRoutine'),
          controller.t('navSettings'),
        ],
      );
      expect(
        localizedDestinations.map((destination) => destination.icon),
        [
          Icons.home_outlined,
          Icons.history_outlined,
          Icons.center_focus_weak_rounded,
          Icons.checklist_outlined,
          Icons.settings_outlined,
        ],
      );
    }
  });

  testWidgets('compact Kurdish bottom navigation fits a narrow RTL screen', (
    tester,
  ) async {
    _setViewport(tester, const Size(320, 568));
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();
    await controller.setLang(AppLang.ku);

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: DashboardScreen(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(tester.takeException(), isNull);
    final destinations =
        tester.widget<GlassBottomNav>(find.byType(GlassBottomNav)).items;
    expect(destinations[3].label, 'ڕۆتین');
    final bottomNavigation = find.byType(GlassBottomNav);
    final navLabels = tester.widgetList<Text>(
      find.descendant(of: bottomNavigation, matching: find.byType(Text)),
    );
    expect(navLabels, hasLength(5));
    expect(navLabels.every((label) => label.maxLines == 1), isTrue);
    expect(
      tester
          .getSize(find.descendant(
            of: bottomNavigation,
            matching: find.text('ڕۆتین'),
          ))
          .height,
      lessThanOrEqualTo(20),
    );
    expect(
      tester
          .getSize(find.descendant(
            of: bottomNavigation,
            matching: find.text('ڕێکخستن'),
          ))
          .height,
      lessThanOrEqualTo(24),
    );
  });

  testWidgets('dashboard adapts navigation for tablet and desktop widths', (
    tester,
  ) async {
    _setViewport(tester, const Size(800, 1000));
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.takeException(), isNull);

    _setViewport(tester, const Size(1440, 1000));
    await tester.pump();
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('SkinAI'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small phone home supports enlarged text without overflow', (
    tester,
  ) async {
    _setViewport(tester, const Size(320, 568));
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(2.0),
            ),
            child: DashboardScreen(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Recent scans'), findsOneWidget);
    expect(find.byType(GlassBottomNav), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop history shows a detail pane and filters scans', (
    tester,
  ) async {
    _setViewport(tester, const Size(1440, 1000));
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();
    await controller.addScan(
      const ScanRecord(
        cls: 'acne',
        conf: 72,
        mel: false,
        ts: 100,
      ),
    );
    await controller.addScan(
      const ScanRecord(
        cls: 'eczema',
        conf: 68,
        mel: false,
        ts: 200,
        summary:
            'A short history preview followed by a detailed summary ending in END_MARKER.',
      ),
    );

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Scan History').first);
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('View full details'), findsOneWidget);
    expect(find.text('eczema'), findsWidgets);
    final summaryDetails = find.byKey(
      const ValueKey('history-summary-details'),
    );
    expect(find.textContaining('END_MARKER'), findsNothing);
    await tester.ensureVisible(summaryDetails);
    await tester.tap(summaryDetails);
    await tester.pumpAndSettle();
    expect(find.textContaining('END_MARKER'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'acne');
    await tester.pump();

    expect(find.text('acne'), findsWidgets);
    expect(find.text('eczema'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings content supports Kurdish Sorani RTL', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();
    controller.setLang(AppLang.ku);

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: SettingsScreen(onLogout: _noopLogout),
          ),
        ),
      ),
    );

    expect(find.text('پێست و زیرەکی دەستکرد'), findsOneWidget);
    expect(
      tester.widgetList<Directionality>(find.byType(Directionality)).any(
          (directionality) =>
              directionality.textDirection == TextDirection.rtl),
      isTrue,
    );
  });

  testWidgets('quiz initializes pending answers after mounting',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();
    controller.pendingAnswers[0] = 1;

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const MaterialApp(home: QuizScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(QuizScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings surfaces and text use high contrast in dark mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: SettingsScreen(onLogout: _noopLogout),
          ),
        ),
      ),
    );

    final settingsPalette = Pal.settingsOf(
      tester.element(find.byType(SettingsScreen)),
    );
    expect(settingsPalette.bg, const Color(0xFF0B0F19));
    expect(settingsPalette.panel, const Color(0xFF151C2C));
    expect(settingsPalette.border, const Color(0xFF263147));
    expect(settingsPalette.text, const Color(0xFFF8FAFC));
    expect(settingsPalette.sub, const Color(0xFF94A3B8));

    final header = tester.widget<Text>(find.text('SKIN & AI'));
    expect(header.style?.color, const Color(0xFF38BDF8));
    final title = tester.widget<Text>(find.text('Primary skincare goal'));
    expect(title.style?.color, settingsPalette.text);
  });

  testWidgets('Kurdish Sorani and Badini both use RTL', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();
    await controller.setLang(AppLang.ku);

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const SkinAIApp(),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final authContext = tester.element(find.byType(AuthScreen));
    expect(MaterialLocalizations.of(authContext), isNotNull);
    expect(Directionality.of(authContext), TextDirection.rtl);

    await controller.setLang(AppLang.badini);
    await tester.pump();
    expect(controller.lang, AppLang.badini);
    expect(
      Directionality.of(tester.element(find.byType(AuthScreen))),
      TextDirection.rtl,
    );
    expect(LocaleHelper.directionFor(const Locale('bad')), TextDirection.rtl);

    await controller.setLang(AppLang.en);
    await tester.pump();
    expect(
      Directionality.of(tester.element(find.byType(AuthScreen))),
      TextDirection.ltr,
    );

    await controller.setLang(AppLang.ku);
    await tester.pump();
    final context = tester.element(find.byType(AuthScreen));
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DashboardScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving profile name closes sheet before updating account state',
      (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const MaterialApp(
          home: Scaffold(
            body: SettingsScreen(onLogout: _noopLogout),
          ),
        ),
      ),
    );

    await tester.tap(find.text('SkinAI member'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('settings are persisted and restored by the app controller', () async {
    SharedPreferences.setMockInitialValues({});
    final reminderService = FakeReminderService();
    final controller = AppController(
      reminderService: reminderService,
      routineScheduler: FakeRoutineScheduler(),
    );
    await controller.init();

    await controller.setSkincareGoal('acne');
    await controller.setReminderTime(const TimeOfDay(hour: 7, minute: 25));
    await controller.setSkinType('sensitive');
    await controller.setAccentColor(const Color(0xFF7B2CBF));
    await controller.setTheme(ThemeMode.light);
    await controller.setLang(AppLang.ar);
    await controller.setNotificationsEnabled(true);

    final restored = AppController(
      reminderService: FakeReminderService(),
      routineScheduler: FakeRoutineScheduler(),
    );
    await restored.init();

    expect(restored.skincareGoal, 'acne');
    expect(restored.reminderHour, 7);
    expect(restored.reminderMinute, 25);
    expect(restored.skinType, 'sensitive');
    expect(restored.accentColor, const Color(0xFF7B2CBF));
    expect(restored.themeMode, ThemeMode.light);
    expect(restored.lang, AppLang.ar);
    expect(restored.notificationsEnabled, isTrue);
    expect(reminderService.enableCalls, 1);
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
}

Future<void> _noopLogout() async {}

class FakeReminderService implements ReminderService {
  @override
  bool get isSupported => true;

  int enableCalls = 0;
  int scheduleCalls = 0;
  int cancelCalls = 0;

  @override
  Future<void> initialize() async {}

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
    enableCalls++;
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
    scheduleCalls++;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }
}

class FakeRoutineScheduler implements RoutineScheduler {
  @override
  bool get isSupported => true;

  @override
  Future<void> initialize(void Function(String? payload) onTap) async {}

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(
    RoutineTask task,
    RoutineNotificationSettings settings, {
    required String language,
    required void Function(String? payload) onTap,
  }) async {}

  @override
  Future<void> cancelTask(String taskId) async {}

  @override
  Future<void> cancelAllRoutineTasks(Iterable<String> taskIds) async {}

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
