import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:skin_ai/design/app_design_system.dart';
import 'package:skin_ai/localization/app_localizations.dart';

import 'admin_api_service.dart';
import 'admin_models.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    required this.api,
    required this.doctorManagementBuilder,
    this.userManagementBuilder,
    this.appointmentManagementBuilder,
    this.tokenChanges,
    super.key,
  });

  final AdminApiService api;
  final WidgetBuilder doctorManagementBuilder;
  final WidgetBuilder? userManagementBuilder;
  final WidgetBuilder? appointmentManagementBuilder;
  final Stream<void>? tokenChanges;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  StreamSubscription<void>? _tokenSubscription;
  AdminDashboardSummary? _summary;
  bool _checkingAccess = true;
  bool _isAdmin = false;
  String? _errorKey;
  int _requestVersion = 0;
  int _periodDays = 7;

  AppLocalizations get _localizations => AppLocalizations.of(context);
  String _t(
    String key, {
    Map<String, String> arguments = const {},
  }) =>
      _localizations.text(
        key,
        domain: 'admin',
        arguments: arguments,
      );

  @override
  void initState() {
    super.initState();
    _tokenSubscription = widget.tokenChanges?.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _requestVersion++;
    _tokenSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load({int? periodDays}) async {
    if (periodDays != null) {
      _periodDays = periodDays;
    }
    final requestVersion = ++_requestVersion;
    if (mounted) {
      setState(() {
        _checkingAccess = true;
        _errorKey = null;
      });
    }
    try {
      final isAdmin = await widget.api.checkAdminStatus();
      if (!mounted || requestVersion != _requestVersion) return;
      if (!isAdmin) {
        setState(() {
          _checkingAccess = false;
          _isAdmin = false;
          _summary = null;
          _errorKey = 'adminDenied';
        });
        return;
      }

      final summary = await widget.api.loadDashboard(days: _periodDays);
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _checkingAccess = false;
        _isAdmin = true;
        _summary = summary;
      });
    } on AdminApiException catch (error) {
      if (!mounted || requestVersion != _requestVersion) return;
      final denied = error.statusCode == 401 || error.statusCode == 403;
      setState(() {
        _checkingAccess = false;
        _isAdmin = !denied && _isAdmin;
        _summary = denied ? null : _summary;
        _errorKey = denied ? 'adminDenied' : 'adminLoadError';
      });
    } on Exception {
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _checkingAccess = false;
        _errorKey = 'adminLoadError';
      });
    }
  }

  Future<void> _openDoctorManagement() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: widget.doctorManagementBuilder),
    );
    if (mounted) _load();
  }

  Future<void> _openUserManagement() async {
    final builder = widget.userManagementBuilder;
    if (builder == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: builder),
    );
    if (mounted) _load();
  }

  Future<void> _openAppointmentManagement() async {
    final builder = widget.appointmentManagementBuilder;
    if (builder == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: builder),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('dashboardTitle')),
        actions: [
          if (_isAdmin)
            IconButton(
              tooltip: _t('retry'),
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_checkingAccess) {
      return Center(
        child: Semantics(
          label: _t('loading'),
          child: const CircularProgressIndicator(),
        ),
      );
    }
    if (_errorKey != null) {
      return _errorState();
    }
    final summary = _summary;
    if (!_isAdmin || summary == null) {
      return _errorState(messageKey: 'adminDenied');
    }
    return _dashboard(summary);
  }

  Widget _errorState({String? messageKey}) {
    final key = messageKey ?? _errorKey ?? 'adminLoadError';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                key == 'adminDenied'
                    ? Icons.lock_outline_rounded
                    : Icons.cloud_off_outlined,
                size: 40,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(height: AppSpacing.x3),
              Text(_t(key), textAlign: TextAlign.center),
              if (key != 'adminDenied') ...[
                const SizedBox(height: AppSpacing.x4),
                FilledButton.tonal(
                  onPressed: _load,
                  child: Text(_t('retry')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _dashboard(AdminDashboardSummary summary) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          constraints.maxWidth,
          AppBreakpoints.contentMaxWidth,
        );
        final columns = width >= 1000
            ? 4
            : width >= AppBreakpoints.compactMaxWidth
                ? 2
                : 1;
        const horizontalPadding = AppSpacing.x4;
        const gap = AppSpacing.x3;
        final available = width - horizontalPadding * 2;
        final tileWidth = (available - gap * (columns - 1)) / columns;
        final totals = [
          _Metric(
            label: _t('totalUsers'),
            value: summary.usersTotal,
            icon: Icons.people_outline_rounded,
          ),
          _Metric(
            label: _t(
              'newUsersForPeriod',
              arguments: {'days': '$_periodDays'},
            ),
            value: _sum(summary.newUsersByDay),
            icon: Icons.person_add_alt_1_outlined,
          ),
          _Metric(
            label: _t(
              'scansForPeriod',
              arguments: {'days': '$_periodDays'},
            ),
            value: summary.scansTotal,
            icon: Icons.document_scanner_outlined,
          ),
          _Metric(
            label: _t(
              'chatMessagesForPeriod',
              arguments: {'days': '$_periodDays'},
            ),
            value: summary.skinchatMessagesTotal,
            icon: Icons.chat_bubble_outline_rounded,
          ),
          _Metric(
            label: _t('publishedDoctors'),
            value: summary.doctorsPublished,
            icon: Icons.medical_services_outlined,
          ),
          _Metric(
            label: _t('pendingDoctors'),
            value: summary.doctorsPending,
            icon: Icons.pending_actions_outlined,
          ),
          _Metric(
            label: _t('waitingReports'),
            value: summary.reportsWaiting,
            icon: Icons.flag_outlined,
          ),
        ];

        return Center(
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(horizontalPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('dashboardSubtitle'),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.x3,
                    runSpacing: AppSpacing.x2,
                    children: [
                      Text(_t('trendPeriod')),
                      SizedBox(
                        width: math.min(220, available),
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: _periodDays,
                          items: [
                            DropdownMenuItem(
                              value: 7,
                              child: Text(
                                _t('last7Days'),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 30,
                              child: Text(
                                _t('last30Days'),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null && value != _periodDays) {
                              _load(periodDays: value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final metric in totals)
                        SizedBox(
                          width: tileWidth,
                          child: _MetricCard(metric: metric),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  _AppointmentsCard(
                    counts: summary.appointmentsByStatus,
                    translate: _t,
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  _TrendCard(
                    title: _t('newUsersTrend'),
                    points: summary.newUsersByDay,
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  _TrendCard(
                    title: _t('scansTrend'),
                    points: summary.scansByDay,
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  _TrendCard(
                    title: _t('chatTrend'),
                    points: summary.skinchatMessagesByDay,
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  _SystemHealthCard(
                    health: summary.systemHealth,
                    translate: _t,
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.medical_services_outlined),
                      title: Text(_t('doctorManagement')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openDoctorManagement,
                    ),
                  ),
                  if (widget.userManagementBuilder != null) ...[
                    const SizedBox(height: AppSpacing.x3),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.people_outline_rounded),
                        title: Text(_t('usersTitle')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _openUserManagement,
                      ),
                    ),
                  ],
                  if (widget.appointmentManagementBuilder != null) ...[
                    const SizedBox(height: AppSpacing.x3),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.event_available_outlined),
                        title: Text(_t('appointmentsTitle')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _openAppointmentManagement,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  int _sum(List<AdminTrendPoint> points) =>
      points.fold(0, (total, point) => total + point.value);
}

class _Metric {
  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Row(
          children: [
            Icon(metric.icon, color: colors.secondary),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metric.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  Text(
                    metric.value.toString(),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.title, required this.points});

  final String title;
  final List<AdminTrendPoint> points;

  @override
  Widget build(BuildContext context) {
    final maximum = points.fold<int>(
      0,
      (current, point) => math.max(current, point.value),
    );
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.x4),
            SizedBox(
              height: 144,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final point in points)
                    Expanded(
                      child: Semantics(
                        label:
                            '${point.date.toIso8601String().substring(0, 10)}'
                            ', ${point.value}',
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SizedBox(
                              height: 18,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  point.value.toString(),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.x1),
                            Container(
                              width: 10,
                              height: maximum == 0
                                  ? 3
                                  : 10 + (64 * point.value / maximum),
                              decoration: BoxDecoration(
                                color: colors.secondary,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.x1),
                            SizedBox(
                              height: 18,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  point.date.day.toString(),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppointmentsCard extends StatelessWidget {
  const _AppointmentsCard({required this.counts, required this.translate});

  final Map<String, int> counts;
  final String Function(String key) translate;

  @override
  Widget build(BuildContext context) {
    final statuses = [
      'pending',
      'confirmed',
      'completed',
      'rejected',
      'cancelled',
      'unknown',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              translate('appointmentsByStatus'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.x2),
            for (final status in statuses)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(translate('status_$status')),
                trailing: Text((counts[status] ?? 0).toString()),
              ),
          ],
        ),
      ),
    );
  }
}

class _SystemHealthCard extends StatelessWidget {
  const _SystemHealthCard({
    required this.health,
    required this.translate,
  });

  final AdminSystemHealth health;
  final String Function(String key) translate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              translate('systemHealth'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.x2),
            _HealthRow(
              label: translate('backendHealth'),
              value: translate('health_${health.status}'),
            ),
            _HealthRow(
              label: translate('mockMode'),
              value: translate(health.mockMode ? 'enabled' : 'disabled'),
            ),
            _HealthRow(
              label: translate('skinchatEnabled'),
              value: translate(
                health.skinchatEnabled ? 'enabled' : 'disabled',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: AppSpacing.x2),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}
