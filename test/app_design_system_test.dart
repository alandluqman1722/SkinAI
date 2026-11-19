import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skin_ai/design/app_components.dart';
import 'package:skin_ai/design/app_design_system.dart';

void main() {
  group('AppBreakpoints', () {
    test('maps widths to compact, medium, and expanded layouts', () {
      expect(AppBreakpoints.fromWidth(599), AppViewport.compact);
      expect(AppBreakpoints.fromWidth(600), AppViewport.medium);
      expect(AppBreakpoints.fromWidth(1024), AppViewport.medium);
      expect(AppBreakpoints.fromWidth(1025), AppViewport.expanded);
    });

    test('caps wide content without changing narrow widths', () {
      expect(AppBreakpoints.contentWidth(360), 360);
      expect(AppBreakpoints.contentWidth(1440), 1100);
    });
  });

  test('builds light and dark Material 3 themes with matching surfaces', () {
    final light = AppTheme.build(Brightness.light);
    final dark = AppTheme.build(Brightness.dark);

    expect(light.useMaterial3, isTrue);
    expect(light.brightness, Brightness.light);
    expect(light.scaffoldBackgroundColor, AppDesignTokens.lightBackground);
    expect(dark.useMaterial3, isTrue);
    expect(dark.brightness, Brightness.dark);
    expect(dark.scaffoldBackgroundColor, AppDesignTokens.darkBackground);
    expect(dark.snackBarTheme.behavior, SnackBarBehavior.floating);
  });

  testWidgets('opaque glass fallback avoids backdrop filtering',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: GlassSurface(child: Text('Readable surface')),
          ),
        ),
      ),
    );

    expect(find.text('Readable surface'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('primary button keeps a single-line accessible label',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrimaryButton(
            label: 'Continue to the next step',
            icon: Icons.arrow_forward,
            onPressed: () {},
          ),
        ),
      ),
    );

    final label = tester.widget<Text>(find.text('Continue to the next step'));
    expect(label.maxLines, 1);
    expect(tester.getSize(find.byType(PrimaryButton)).height, 48);
  });
}
