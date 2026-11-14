import 'package:flutter_test/flutter_test.dart';
import 'package:skin_ai/notification_time_rules.dart';

void main() {
  test('quiet hours support daytime windows and exclusive end times', () {
    expect(NotificationTimeRules.isWithinQuietHours(540, 480, 600), isTrue);
    expect(NotificationTimeRules.isWithinQuietHours(600, 480, 600), isFalse);
    expect(NotificationTimeRules.isWithinQuietHours(420, 480, 600), isFalse);
  });

  test('quiet hours support intervals crossing midnight', () {
    expect(NotificationTimeRules.isWithinQuietHours(23 * 60, 22 * 60, 7 * 60),
        isTrue);
    expect(NotificationTimeRules.isWithinQuietHours(6 * 60, 22 * 60, 7 * 60),
        isTrue);
    expect(NotificationTimeRules.isWithinQuietHours(12 * 60, 22 * 60, 7 * 60),
        isFalse);
  });

  test('equal boundaries represent an all-day quiet period', () {
    expect(NotificationTimeRules.isWithinQuietHours(5, 400, 400), isTrue);
    expect(NotificationTimeRules.isWithinQuietHours(900, 400, 400), isTrue);
  });
}
