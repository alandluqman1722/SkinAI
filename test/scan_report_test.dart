import 'package:flutter_test/flutter_test.dart';
import 'package:skin_ai/scan_report.dart';

void main() {
  test('PDF report contains a valid PDF document', () async {
    final bytes = await buildScanReportPdf(
      result: 'Mock screening result',
      confidencePercent: 84,
      scannedAt: DateTime.utc(2026, 10, 29, 12),
      summary: 'Mock **screening** summary.',
      localize: (key, {arguments = const {}}) => key,
    );

    expect(bytes.length, greaterThan(500));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
