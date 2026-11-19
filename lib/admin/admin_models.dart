class AdminTrendPoint {
  const AdminTrendPoint({required this.date, required this.value});

  final DateTime date;
  final int value;

  factory AdminTrendPoint.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['date'] is! String ||
        value['value'] is! int) {
      throw const FormatException('Invalid admin trend point.');
    }
    return AdminTrendPoint(
      date: DateTime.parse(value['date'] as String),
      value: value['value'] as int,
    );
  }
}

class AdminSystemHealth {
  const AdminSystemHealth({
    required this.status,
    required this.mockMode,
    required this.skinchatEnabled,
  });

  final String status;
  final bool mockMode;
  final bool skinchatEnabled;

  factory AdminSystemHealth.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['status'] is! String ||
        value['mock_mode'] is! bool ||
        value['skinchat_enabled'] is! bool) {
      throw const FormatException('Invalid admin system health.');
    }
    return AdminSystemHealth(
      status: value['status'] as String,
      mockMode: value['mock_mode'] as bool,
      skinchatEnabled: value['skinchat_enabled'] as bool,
    );
  }
}

class AdminDashboardSummary {
  const AdminDashboardSummary({
    required this.generatedAt,
    required this.periodDays,
    required this.usersTotal,
    required this.newUsersByDay,
    required this.scansByDay,
    required this.scansTotal,
    required this.skinchatMessagesByDay,
    required this.skinchatMessagesTotal,
    required this.appointmentsByStatus,
    required this.doctorsPublished,
    required this.doctorsPending,
    required this.reportsWaiting,
    required this.systemHealth,
  });

  final DateTime generatedAt;
  final int periodDays;
  final int usersTotal;
  final List<AdminTrendPoint> newUsersByDay;
  final List<AdminTrendPoint> scansByDay;
  final int scansTotal;
  final List<AdminTrendPoint> skinchatMessagesByDay;
  final int skinchatMessagesTotal;
  final Map<String, int> appointmentsByStatus;
  final int doctorsPublished;
  final int doctorsPending;
  final int reportsWaiting;
  final AdminSystemHealth systemHealth;

  factory AdminDashboardSummary.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid admin dashboard response.');
    }
    final usersTotal = value['users_total'];
    final periodDays = value['period_days'];
    final scansTotal = value['scans_total'];
    final chatTotal = value['skinchat_messages_total'];
    final doctorsPublished = value['doctors_published'];
    final doctorsPending = value['doctors_pending'];
    final reportsWaiting = value['reports_waiting'];
    final appointmentData = value['appointments_by_status'];
    if (value['generated_at'] is! String ||
        periodDays is! int ||
        usersTotal is! int ||
        scansTotal is! int ||
        chatTotal is! int ||
        doctorsPublished is! int ||
        doctorsPending is! int ||
        reportsWaiting is! int ||
        appointmentData is! Map<String, dynamic>) {
      throw const FormatException('Invalid admin dashboard response.');
    }
    final appointments = <String, int>{};
    for (final entry in appointmentData.entries) {
      if (entry.value is! int) {
        throw const FormatException('Invalid appointment totals.');
      }
      appointments[entry.key] = entry.value as int;
    }
    return AdminDashboardSummary(
      generatedAt: DateTime.parse(value['generated_at'] as String),
      periodDays: periodDays,
      usersTotal: usersTotal,
      newUsersByDay: _trendList(value['new_users_by_day']),
      scansByDay: _trendList(value['scans_by_day']),
      scansTotal: scansTotal,
      skinchatMessagesByDay: _trendList(value['skinchat_messages_by_day']),
      skinchatMessagesTotal: chatTotal,
      appointmentsByStatus: appointments,
      doctorsPublished: doctorsPublished,
      doctorsPending: doctorsPending,
      reportsWaiting: reportsWaiting,
      systemHealth: AdminSystemHealth.fromJson(value['system_health']),
    );
  }

  static List<AdminTrendPoint> _trendList(Object? value) {
    if (value is! List<dynamic>) {
      throw const FormatException('Invalid admin trend data.');
    }
    return [
      for (final point in value) AdminTrendPoint.fromJson(point),
    ];
  }
}

class AdminUser {
  const AdminUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.createdAt,
    required this.lastSignIn,
    required this.emailVerified,
    required this.disabled,
    required this.blocked,
    required this.plan,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final DateTime createdAt;
  final DateTime? lastSignIn;
  final bool emailVerified;
  final bool disabled;
  final bool blocked;
  final String plan;

  factory AdminUser.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['uid'] is! String ||
        value['created_at'] is! String ||
        value['email_verified'] is! bool ||
        value['disabled'] is! bool ||
        value['blocked'] is! bool ||
        value['plan'] is! String ||
        (value['email'] != null && value['email'] is! String) ||
        (value['display_name'] != null && value['display_name'] is! String) ||
        (value['last_sign_in'] != null && value['last_sign_in'] is! String)) {
      throw const FormatException('Invalid admin user response.');
    }
    return AdminUser(
      uid: value['uid'] as String,
      email: value['email'] as String?,
      displayName: value['display_name'] as String?,
      createdAt: DateTime.parse(value['created_at'] as String),
      lastSignIn: value['last_sign_in'] == null
          ? null
          : DateTime.parse(value['last_sign_in'] as String),
      emailVerified: value['email_verified'] as bool,
      disabled: value['disabled'] as bool,
      blocked: value['blocked'] as bool,
      plan: value['plan'] as String,
    );
  }
}

class AdminUsersPage {
  const AdminUsersPage({required this.users, required this.nextCursor});

  final List<AdminUser> users;
  final String? nextCursor;

  factory AdminUsersPage.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['users'] is! List<dynamic> ||
        (value['next_cursor'] != null && value['next_cursor'] is! String)) {
      throw const FormatException('Invalid admin users page.');
    }
    return AdminUsersPage(
      users: [
        for (final user in value['users'] as List<dynamic>)
          AdminUser.fromJson(user),
      ],
      nextCursor: value['next_cursor'] as String?,
    );
  }
}

class AdminUserUsage {
  const AdminUserUsage({
    required this.date,
    required this.dailySkinchatUsage,
    required this.scansTotal,
  });

  final DateTime date;
  final int dailySkinchatUsage;
  final int scansTotal;

  factory AdminUserUsage.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['date'] is! String ||
        value['daily_skinchat_usage'] is! int ||
        value['scans_total'] is! int) {
      throw const FormatException('Invalid admin user usage response.');
    }
    return AdminUserUsage(
      date: DateTime.parse(value['date'] as String),
      dailySkinchatUsage: value['daily_skinchat_usage'] as int,
      scansTotal: value['scans_total'] as int,
    );
  }
}

class AdminAppointment {
  const AdminAppointment({
    required this.id,
    required this.doctorId,
    required this.doctorName,
    required this.clinicId,
    required this.clinicName,
    required this.city,
    required this.date,
    required this.time,
    required this.status,
  });

  final String id;
  final String doctorId;
  final String doctorName;
  final String clinicId;
  final String clinicName;
  final String city;
  final DateTime date;
  final String time;
  final String status;

  factory AdminAppointment.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['id'] is! String ||
        value['doctor_id'] is! String ||
        value['doctor_name'] is! String ||
        value['clinic_id'] is! String ||
        value['clinic_name'] is! String ||
        value['city'] is! String ||
        value['appointment_date'] is! String ||
        value['appointment_time'] is! String ||
        value['status'] is! String) {
      throw const FormatException('Invalid admin appointment response.');
    }
    return AdminAppointment(
      id: value['id'] as String,
      doctorId: value['doctor_id'] as String,
      doctorName: value['doctor_name'] as String,
      clinicId: value['clinic_id'] as String,
      clinicName: value['clinic_name'] as String,
      city: value['city'] as String,
      date: DateTime.parse(value['appointment_date'] as String),
      time: value['appointment_time'] as String,
      status: value['status'] as String,
    );
  }
}

class AdminAppointmentsPage {
  const AdminAppointmentsPage({
    required this.appointments,
    required this.nextCursor,
  });

  final List<AdminAppointment> appointments;
  final String? nextCursor;

  factory AdminAppointmentsPage.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['appointments'] is! List<dynamic> ||
        (value['next_cursor'] != null && value['next_cursor'] is! String)) {
      throw const FormatException('Invalid admin appointments page.');
    }
    return AdminAppointmentsPage(
      appointments: [
        for (final item in value['appointments'] as List<dynamic>)
          AdminAppointment.fromJson(item),
      ],
      nextCursor: value['next_cursor'] as String?,
    );
  }
}
