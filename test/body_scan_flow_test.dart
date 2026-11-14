import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skin_ai/main.dart';

void main() {
  testWidgets('scanner offers optional fields and a no-location path', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );

    await tester.tap(find.byType(NavigationDestination).at(2));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Continue without location or concern'), findsOneWidget);
    expect(
      find.text(
        'This is a screening tool, not a medical diagnosis. Please consult a healthcare professional.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Continue without location or concern'));
    await tester.pump();

    expect(find.text('Choose a photo to analyze'), findsOneWidget);
    expect(find.text('Choose from Gallery'), findsOneWidget);
    expect(find.text('Open Camera'), findsOneWidget);
    expect(find.text('Analyze image'), findsOneWidget);
    expect(find.text('Save scan details to my account'), findsOneWidget);
    expect(find.text('Also store the original image'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(4));
    expect(find.textContaining('HAM10000'), findsNothing);
    expect(find.textContaining('Ivy AI'), findsNothing);

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
