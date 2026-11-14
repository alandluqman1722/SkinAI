import 'package:flutter_test/flutter_test.dart';
import 'package:skin_ai/main.dart';

void main() {
  test('accepts new provider labels and preserves the Markdown summary', () {
    final result = ScanResult.fromJson({
      'result': 'A future provider label',
      'confidence': 0.84,
      'summary': '## Summary\n\n- **Markdown** stays intact.',
      'id': 'scan-123',
      'timestamp': '2026-10-29T12:00:00+00:00',
      'discordant': true,
    });

    expect(result.cls, 'A future provider label');
    expect(result.confidence, 84);
    expect(result.summary, '## Summary\n\n- **Markdown** stays intact.');
    expect(result.scanId, 'scan-123');
    expect(result.timestamp, DateTime.parse('2026-10-29T12:00:00+00:00'));
  });
}
