import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skin_ai/localization/locale_helper.dart';
import 'package:skin_ai/navigation/edge_swipe_navigation.dart';

void main() {
  for (final (name, locale, isRtl) in [
    ('Sorani Kurdish', const Locale('ku'), true),
    ('Badini Kurdish', const Locale('bad'), true),
    ('Arabic', const Locale('ar'), true),
    ('English', const Locale('en'), false),
  ]) {
    testWidgets('$name edge swipes follow the current locale direction',
        (tester) async {
      var backCount = 0;
      var forwardCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: LocaleHelper.directionFor(locale),
            child: EdgeSwipeNavigation(
              onBack: () => backCount++,
              onForward: () => forwardCount++,
              child: const Scaffold(body: SizedBox.expand()),
            ),
          ),
        ),
      );

      final toRight = await tester.startGesture(const Offset(10, 300));
      await toRight.moveTo(const Offset(130, 300));
      await toRight.up();
      await tester.pump();

      expect(backCount, isRtl ? 0 : 1);
      expect(forwardCount, isRtl ? 1 : 0);
    });

    testWidgets('$name section swipes advance one step and respect bounds',
        (tester) async {
      var selectedIndex = 2;

      Widget app() => MaterialApp(
            home: Directionality(
              textDirection: LocaleHelper.directionFor(locale),
              child: EdgeSwipeNavigation(
                onBack: selectedIndex > 0 ? () => selectedIndex-- : null,
                onForward: selectedIndex < 4 ? () => selectedIndex++ : null,
                child: const Scaffold(body: SizedBox.expand()),
              ),
            ),
          );

      await tester.pumpWidget(app());

      Future<void> swipe({required bool right}) async {
        final gesture = await tester.startGesture(
          Offset(right ? 10 : 790, 300),
        );
        await gesture.moveTo(Offset(right ? 130 : 670, 300));
        await gesture.up();
        await tester.pumpAndSettle();
      }

      final swipeRightAdvances = isRtl;
      await swipe(right: swipeRightAdvances);
      expect(selectedIndex, 3);
      await tester.pumpWidget(app());

      await swipe(right: swipeRightAdvances);
      expect(selectedIndex, 4);
      await tester.pumpWidget(app());

      await swipe(right: swipeRightAdvances);
      expect(selectedIndex, 4);
      await tester.pumpWidget(app());

      await swipe(right: !swipeRightAdvances);
      expect(selectedIndex, 3);
      await tester.pumpWidget(app());

      await swipe(right: !swipeRightAdvances);
      expect(selectedIndex, 2);
      await tester.pumpWidget(app());

      await swipe(right: !swipeRightAdvances);
      expect(selectedIndex, 1);
      await tester.pumpWidget(app());

      await swipe(right: !swipeRightAdvances);
      expect(selectedIndex, 0);
      await tester.pumpWidget(app());

      await swipe(right: !swipeRightAdvances);
      expect(selectedIndex, 0);
    });
  }

  testWidgets('changing Directionality updates swipe mapping immediately',
      (tester) async {
    var textDirection = TextDirection.ltr;
    var backCount = 0;
    var forwardCount = 0;

    Widget app() => MaterialApp(
          home: Directionality(
            textDirection: textDirection,
            child: EdgeSwipeNavigation(
              key: const ValueKey('edge-navigation'),
              onBack: () => backCount++,
              onForward: () => forwardCount++,
              child: const Scaffold(body: SizedBox.expand()),
            ),
          ),
        );

    await tester.pumpWidget(app());
    final ltrSwipe = await tester.startGesture(const Offset(10, 300));
    await ltrSwipe.moveTo(const Offset(130, 300));
    await ltrSwipe.up();
    await tester.pump();
    expect(backCount, 1);
    expect(forwardCount, 0);
    await tester.pumpAndSettle();

    textDirection = TextDirection.rtl;
    await tester.pumpWidget(app());
    final rtlSwipe = await tester.startGesture(const Offset(10, 300));
    await rtlSwipe.moveTo(const Offset(130, 300));
    await rtlSwipe.up();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(backCount, 1);
    expect(forwardCount, 1);
  });

  testWidgets('page follows horizontal drag and settles smoothly',
      (tester) async {
    var forwardCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: EdgeSwipeNavigation(
            onForward: () => forwardCount++,
            child: const Scaffold(
              body: Align(
                alignment: Alignment.centerLeft,
                child: Text('Page'),
              ),
            ),
          ),
        ),
      ),
    );

    final before = tester.getTopLeft(find.text('Page')).dx;
    final initialSize = tester.getSize(find.byType(Scaffold));
    final gesture = await tester.startGesture(const Offset(10, 300));
    await gesture.moveTo(const Offset(100, 300));
    await tester.pump();
    expect(tester.getTopLeft(find.text('Page')).dx, greaterThan(before));
    expect(tester.getSize(find.byType(Scaffold)), initialSize);

    await gesture.up();
    await tester.pump();
    expect(forwardCount, 1);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Page')).dx, closeTo(before, 1));
  });

  testWidgets('route edge swipe pops the real route in the current direction',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    var textDirection = TextDirection.rtl;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) => Directionality(
          textDirection: textDirection,
          child: EdgeSwipeNavigation(
            canGoBack: () => navigatorKey.currentState?.canPop() ?? false,
            onBack: () => navigatorKey.currentState?.pop(),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(
                    body: Center(child: Text('Pushed route')),
                  ),
                ),
              ),
              child: const Text('Open route'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open route'));
    await tester.pumpAndSettle();
    expect(navigatorKey.currentState?.canPop(), isTrue);

    final gesture = await tester.startGesture(const Offset(790, 300));
    await gesture.moveTo(const Offset(670, 300));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Open route'), findsOneWidget);
    expect(navigatorKey.currentState?.canPop(), isFalse);

    textDirection = TextDirection.ltr;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) => Directionality(
          textDirection: textDirection,
          child: EdgeSwipeNavigation(
            canGoBack: () => navigatorKey.currentState?.canPop() ?? false,
            onBack: () => navigatorKey.currentState?.pop(),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(
                    body: Center(child: Text('Pushed route')),
                  ),
                ),
              ),
              child: const Text('Open route'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open route'));
    await tester.pumpAndSettle();

    final ltrGesture = await tester.startGesture(const Offset(10, 300));
    await ltrGesture.moveTo(const Offset(130, 300));
    await ltrGesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Open route'), findsOneWidget);
    expect(navigatorKey.currentState?.canPop(), isFalse);
  });

  testWidgets('LTR rightward edge swipe invokes back without pushing a route',
      (tester) async {
    var backCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EdgeSwipeNavigation(
          onBack: () => backCount++,
          child: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(10, 300));
    await gesture.moveTo(const Offset(130, 300));
    await gesture.up();
    await tester.pump();

    expect(backCount, 1);
  });

  testWidgets('LTR leftward edge swipe invokes forward when available',
      (tester) async {
    var forwardCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EdgeSwipeNavigation(
          onForward: () => forwardCount++,
          child: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(790, 300));
    await gesture.moveTo(const Offset(670, 300));
    await gesture.up();
    await tester.pump();

    expect(forwardCount, 1);
  });

  testWidgets('vertical and short movements do not trigger navigation',
      (tester) async {
    var navigationCount = 0;
    final scrollController = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: EdgeSwipeNavigation(
          onBack: () => navigationCount++,
          onForward: () => navigationCount++,
          child: Scaffold(
            body: ListView(
              controller: scrollController,
              children: const [SizedBox(height: 1200)],
            ),
          ),
        ),
      ),
    );

    final vertical = await tester.startGesture(const Offset(10, 200));
    await vertical.moveTo(const Offset(18, 80));
    await vertical.up();
    await tester.pumpAndSettle();

    expect(navigationCount, 0);
    expect(scrollController.offset, greaterThan(0));
    scrollController.dispose();
  });

  testWidgets('AppBar back button pops the actual previous route',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Second screen')),
                      body: const SizedBox.expand(),
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsOneWidget);
    expect(navigatorKey.currentState?.canPop(), isFalse);
  });
}
