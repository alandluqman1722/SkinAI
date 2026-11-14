enum RoutinePeriod { morning, afternoon, evening, bedtime }

class RoutineTask {
  const RoutineTask({
    required this.id,
    required this.title,
    required this.period,
    required this.weekdays,
    required this.reminderMinutes,
    required this.reminderEnabled,
    this.completedDays = const {},
  });

  final String id;
  final String title;
  final RoutinePeriod period;
  final List<int> weekdays;
  final int reminderMinutes;
  final bool reminderEnabled;
  final Set<String> completedDays;

  bool appliesTo(DateTime day) => weekdays.contains(day.weekday);

  bool isCompletedOn(DateTime day) => completedDays.contains(dayKey(day));

  RoutineTask copyWith({
    String? title,
    RoutinePeriod? period,
    List<int>? weekdays,
    int? reminderMinutes,
    bool? reminderEnabled,
    Set<String>? completedDays,
  }) =>
      RoutineTask(
        id: id,
        title: title ?? this.title,
        period: period ?? this.period,
        weekdays: weekdays ?? this.weekdays,
        reminderMinutes: reminderMinutes ?? this.reminderMinutes,
        reminderEnabled: reminderEnabled ?? this.reminderEnabled,
        completedDays: completedDays ?? this.completedDays,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'period': period.name,
        'weekdays': weekdays,
        'reminderMinutes': reminderMinutes,
        'reminderEnabled': reminderEnabled,
        'completedDays': completedDays.toList(),
      };

  factory RoutineTask.fromJson(Map<String, dynamic> json) => RoutineTask(
        id: json['id'] as String,
        title: json['title'] as String,
        period: RoutinePeriod.values.firstWhere(
          (value) => value.name == json['period'],
          orElse: () => RoutinePeriod.morning,
        ),
        weekdays: (json['weekdays'] as List? ?? const [1, 2, 3, 4, 5, 6, 7])
            .map((value) => value as int)
            .where((value) => value >= 1 && value <= 7)
            .toList(),
        reminderMinutes: json['reminderMinutes'] as int? ?? 480,
        reminderEnabled: json['reminderEnabled'] as bool? ?? false,
        completedDays: (json['completedDays'] as List? ?? const [])
            .map((value) => value as String)
            .toSet(),
      );

  static String dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

class RoutineNotification {
  const RoutineNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.createdAt,
    required this.read,
    this.deepLink,
    this.important = false,
    this.type,
    this.titleKey,
    this.bodyKey,
    this.parameters = const {},
  });

  final String id;
  final String title;
  final String body;
  final String category;
  final DateTime createdAt;
  final bool read;
  final String? deepLink;
  final bool important;
  final String? type;
  final String? titleKey;
  final String? bodyKey;
  final Map<String, String> parameters;

  RoutineNotification copyWith({
    bool? read,
    String? title,
    String? body,
    String? titleKey,
    String? bodyKey,
  }) =>
      RoutineNotification(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        category: category,
        createdAt: createdAt,
        read: read ?? this.read,
        deepLink: deepLink,
        important: important,
        type: type,
        titleKey: titleKey ?? this.titleKey,
        bodyKey: bodyKey ?? this.bodyKey,
        parameters: parameters,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'category': category,
        'createdAt': createdAt.toIso8601String(),
        'read': read,
        'deepLink': deepLink,
        'important': important,
        'type': type,
        'titleKey': titleKey,
        'bodyKey': bodyKey,
        'parameters': parameters,
      };

  factory RoutineNotification.fromJson(Map<String, dynamic> json) =>
      RoutineNotification(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        category: json['category'] as String? ?? 'routine',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        read: json['read'] as bool? ?? false,
        deepLink: json['deepLink'] as String?,
        important: json['important'] as bool? ?? false,
        type: json['type'] as String?,
        titleKey: json['titleKey'] as String?,
        bodyKey: json['bodyKey'] as String?,
        parameters: (json['parameters'] as Map? ?? const {}).map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        ),
      );
}

class RoutineNotificationSettings {
  const RoutineNotificationSettings({
    this.masterEnabled = false,
    this.dailyEnabled = true,
    this.morningEnabled = true,
    this.eveningEnabled = true,
    this.sunscreenEnabled = true,
    this.hydrationEnabled = true,
    this.aiScanEnabled = false,
    this.weeklySummaryEnabled = false,
    this.doctorMessagesEnabled = true,
    this.appointmentRemindersEnabled = true,
    this.subscriptionAlertsEnabled = true,
    this.systemUpdatesEnabled = true,
    this.securityAlertsEnabled = true,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.privatePreview = true,
    this.quietHoursEnabled = false,
    this.quietStartMinutes = 22 * 60,
    this.quietEndMinutes = 7 * 60,
  });

  final bool masterEnabled;
  final bool dailyEnabled;
  final bool morningEnabled;
  final bool eveningEnabled;
  final bool sunscreenEnabled;
  final bool hydrationEnabled;
  final bool aiScanEnabled;
  final bool weeklySummaryEnabled;
  final bool doctorMessagesEnabled;
  final bool appointmentRemindersEnabled;
  final bool subscriptionAlertsEnabled;
  final bool systemUpdatesEnabled;
  final bool securityAlertsEnabled;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool privatePreview;
  final bool quietHoursEnabled;
  final int quietStartMinutes;
  final int quietEndMinutes;

  RoutineNotificationSettings copyWith({
    bool? masterEnabled,
    bool? dailyEnabled,
    bool? morningEnabled,
    bool? eveningEnabled,
    bool? sunscreenEnabled,
    bool? hydrationEnabled,
    bool? aiScanEnabled,
    bool? weeklySummaryEnabled,
    bool? doctorMessagesEnabled,
    bool? appointmentRemindersEnabled,
    bool? subscriptionAlertsEnabled,
    bool? systemUpdatesEnabled,
    bool? securityAlertsEnabled,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? privatePreview,
    bool? quietHoursEnabled,
    int? quietStartMinutes,
    int? quietEndMinutes,
  }) =>
      RoutineNotificationSettings(
        masterEnabled: masterEnabled ?? this.masterEnabled,
        dailyEnabled: dailyEnabled ?? this.dailyEnabled,
        morningEnabled: morningEnabled ?? this.morningEnabled,
        eveningEnabled: eveningEnabled ?? this.eveningEnabled,
        sunscreenEnabled: sunscreenEnabled ?? this.sunscreenEnabled,
        hydrationEnabled: hydrationEnabled ?? this.hydrationEnabled,
        aiScanEnabled: aiScanEnabled ?? this.aiScanEnabled,
        weeklySummaryEnabled: weeklySummaryEnabled ?? this.weeklySummaryEnabled,
        doctorMessagesEnabled:
            doctorMessagesEnabled ?? this.doctorMessagesEnabled,
        appointmentRemindersEnabled:
            appointmentRemindersEnabled ?? this.appointmentRemindersEnabled,
        subscriptionAlertsEnabled:
            subscriptionAlertsEnabled ?? this.subscriptionAlertsEnabled,
        systemUpdatesEnabled: systemUpdatesEnabled ?? this.systemUpdatesEnabled,
        securityAlertsEnabled:
            securityAlertsEnabled ?? this.securityAlertsEnabled,
        soundEnabled: soundEnabled ?? this.soundEnabled,
        vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
        privatePreview: privatePreview ?? this.privatePreview,
        quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
        quietStartMinutes: quietStartMinutes ?? this.quietStartMinutes,
        quietEndMinutes: quietEndMinutes ?? this.quietEndMinutes,
      );

  Map<String, Object?> toJson() => {
        'masterEnabled': masterEnabled,
        'dailyEnabled': dailyEnabled,
        'morningEnabled': morningEnabled,
        'eveningEnabled': eveningEnabled,
        'sunscreenEnabled': sunscreenEnabled,
        'hydrationEnabled': hydrationEnabled,
        'aiScanEnabled': aiScanEnabled,
        'weeklySummaryEnabled': weeklySummaryEnabled,
        'doctorMessagesEnabled': doctorMessagesEnabled,
        'appointmentRemindersEnabled': appointmentRemindersEnabled,
        'subscriptionAlertsEnabled': subscriptionAlertsEnabled,
        'systemUpdatesEnabled': systemUpdatesEnabled,
        'securityAlertsEnabled': securityAlertsEnabled,
        'soundEnabled': soundEnabled,
        'vibrationEnabled': vibrationEnabled,
        'privatePreview': privatePreview,
        'quietHoursEnabled': quietHoursEnabled,
        'quietStartMinutes': quietStartMinutes,
        'quietEndMinutes': quietEndMinutes,
      };

  factory RoutineNotificationSettings.fromJson(Map<String, dynamic> json) =>
      RoutineNotificationSettings(
        masterEnabled: json['masterEnabled'] as bool? ?? false,
        dailyEnabled: json['dailyEnabled'] as bool? ?? true,
        morningEnabled: json['morningEnabled'] as bool? ?? true,
        eveningEnabled: json['eveningEnabled'] as bool? ?? true,
        sunscreenEnabled: json['sunscreenEnabled'] as bool? ?? true,
        hydrationEnabled: json['hydrationEnabled'] as bool? ?? true,
        aiScanEnabled: json['aiScanEnabled'] as bool? ?? false,
        weeklySummaryEnabled: json['weeklySummaryEnabled'] as bool? ?? false,
        doctorMessagesEnabled: json['doctorMessagesEnabled'] as bool? ?? true,
        appointmentRemindersEnabled:
            json['appointmentRemindersEnabled'] as bool? ?? true,
        subscriptionAlertsEnabled:
            json['subscriptionAlertsEnabled'] as bool? ?? true,
        systemUpdatesEnabled: json['systemUpdatesEnabled'] as bool? ?? true,
        securityAlertsEnabled: json['securityAlertsEnabled'] as bool? ?? true,
        soundEnabled: json['soundEnabled'] as bool? ?? true,
        vibrationEnabled: json['vibrationEnabled'] as bool? ?? true,
        privatePreview: json['privatePreview'] as bool? ?? true,
        quietHoursEnabled: json['quietHoursEnabled'] as bool? ?? false,
        quietStartMinutes: json['quietStartMinutes'] as int? ?? 22 * 60,
        quietEndMinutes: json['quietEndMinutes'] as int? ?? 7 * 60,
      );
}

class WidgetCustomization {
  const WidgetCustomization({
    this.style = 'dailyProgress',
    this.accentColor = 0xFF168CFF,
    this.theme = 'system',
    this.compact = false,
    this.showProgress = true,
    this.showTasks = true,
    this.dataPeriod = 'daily',
  });

  static const styles = [
    'dailyProgress',
    'morningRoutine',
    'eveningRoutine',
    'weeklyRoutine',
    'minimal',
    'statistics',
    'quickActions',
  ];

  final String style;
  final int accentColor;
  final String theme;
  final bool compact;
  final bool showProgress;
  final bool showTasks;
  final String dataPeriod;

  WidgetCustomization copyWith({
    String? style,
    int? accentColor,
    String? theme,
    bool? compact,
    bool? showProgress,
    bool? showTasks,
    String? dataPeriod,
  }) =>
      WidgetCustomization(
        style: style ?? this.style,
        accentColor: accentColor ?? this.accentColor,
        theme: theme ?? this.theme,
        compact: compact ?? this.compact,
        showProgress: showProgress ?? this.showProgress,
        showTasks: showTasks ?? this.showTasks,
        dataPeriod: dataPeriod ?? this.dataPeriod,
      );

  Map<String, Object?> toJson() => {
        'style': style,
        'accentColor': accentColor,
        'theme': theme,
        'compact': compact,
        'showProgress': showProgress,
        'showTasks': showTasks,
        'dataPeriod': dataPeriod,
      };

  factory WidgetCustomization.fromJson(Map<String, dynamic> json) {
    final style = json['style'] as String? ?? 'dailyProgress';
    return WidgetCustomization(
      style: styles.contains(style) ? style : 'dailyProgress',
      accentColor: json['accentColor'] as int? ?? 0xFF168CFF,
      theme: json['theme'] as String? ?? 'system',
      compact: json['compact'] as bool? ?? false,
      showProgress: json['showProgress'] as bool? ?? true,
      showTasks: json['showTasks'] as bool? ?? true,
      dataPeriod: json['dataPeriod'] as String? ?? 'daily',
    );
  }
}
