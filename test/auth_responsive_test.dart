import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skin_ai/main.dart';

void main() {
  testWidgets('desktop auth uses branded panel beside the form',
      (tester) async {
    _setViewport(tester, const Size(1440, 1000));
    addTearDown(_resetViewport(tester));
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const MaterialApp(home: AuthScreen(startLogin: true)),
      ),
    );
    await tester.pump();

    expect(find.text('Welcome to SkinAI'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone auth supports password visibility and hides Apple sign-in',
      (tester) async {
    _setViewport(tester, const Size(320, 568));
    addTearDown(_resetViewport(tester));
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: const AuthScreen(startLogin: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Sign in with Apple'), findsNothing);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
      isTrue,
    );

    await tester.ensureVisible(find.byTooltip('Show password'));
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();

    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
}

void Function() _resetViewport(WidgetTester tester) => () {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    };
