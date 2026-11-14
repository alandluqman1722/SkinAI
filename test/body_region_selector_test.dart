import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skin_ai/skin_scan/body_region_selector.dart';

void main() {
  test('known body regions are selectable for optional scan metadata', () {
    expect(bodyRegionOptions, isNotEmpty);
    expect(
      bodyRegionOptions.every((region) => isSelectableBodyRegion(region.id)),
      isTrue,
    );
    expect(isSelectableBodyRegion('not-a-body-region'), isFalse);
    expect(
      bodyRegionOptions.map((region) => region.id).toSet().length,
      bodyRegionOptions.length,
    );
  });

  testWidgets('searchable body-area list selects known locations', (
    tester,
  ) async {
    BodyRegionOption? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BodyRegionSelector(
              selectedRegion: null,
              accentColor: Colors.blue,
              panelColor: Colors.white,
              textColor: Colors.black,
              mutedColor: Colors.grey,
              borderColor: Colors.grey.shade300,
              onSelected: (region) => selected = region,
              onCleared: () => selected = null,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'chest');
    await tester.pumpAndSettle();
    final chest = find.text('Chest');
    expect(chest, findsOneWidget);
    await tester.ensureVisible(chest);
    await tester.pumpAndSettle();
    await tester.tap(chest);
    expect(selected?.id, 'chest');
  });
}
