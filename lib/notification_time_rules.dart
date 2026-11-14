class NotificationTimeRules {
  const NotificationTimeRules._();

  static bool isWithinQuietHours(int minutes, int start, int end) {
    if (start == end) return true;
    if (start < end) return minutes >= start && minutes < end;
    return minutes >= start || minutes < end;
  }
}
