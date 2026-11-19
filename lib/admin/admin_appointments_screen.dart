import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:skin_ai/design/app_design_system.dart';
import 'package:skin_ai/localization/app_localizations.dart';

import 'admin_api_service.dart';
import 'admin_models.dart';

class AdminAppointmentsScreen extends StatefulWidget {
  const AdminAppointmentsScreen({
    required this.api,
    this.tokenChanges,
    super.key,
  });

  final AdminApiService api;
  final Stream<void>? tokenChanges;

  @override
  State<AdminAppointmentsScreen> createState() =>
      _AdminAppointmentsScreenState();
}

class _AdminAppointmentsScreenState extends State<AdminAppointmentsScreen> {
  final _doctorController = TextEditingController();
  final List<String?> _cursorHistory = [null];
  StreamSubscription<void>? _tokenSubscription;
  AdminAppointmentsPage? _page;
  bool _checkingAccess = true;
  bool _isAdmin = false;
  bool _loading = false;
  String? _errorKey;
  String _statusFilter = 'all';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String? _busyAppointmentId;
  int _requestVersion = 0;

  AppLocalizations get _localizations => AppLocalizations.of(context);
  String _t(String key, {Map<String, String> arguments = const {}}) =>
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
    _doctorController.dispose();
    super.dispose();
  }

  Future<void> _load({String? cursor, bool verifyAccess = true}) async {
    final requestVersion = ++_requestVersion;
    setState(() {
      _loading = true;
      _checkingAccess = verifyAccess;
      _errorKey = null;
    });
    try {
      if (verifyAccess) {
        final isAdmin = await widget.api.checkAdminStatus();
        if (!mounted || requestVersion != _requestVersion) return;
        if (!isAdmin) {
          setState(() {
            _checkingAccess = false;
            _loading = false;
            _isAdmin = false;
            _page = null;
            _errorKey = 'adminDenied';
          });
          return;
        }
      }

      final page = await widget.api.loadAppointments(
        status: _statusFilter == 'all' ? null : _statusFilter,
        doctorId: _doctorController.text.trim(),
        dateFrom: _dateFrom == null ? null : _dateOnly(_dateFrom!),
        dateTo: _dateTo == null ? null : _dateOnly(_dateTo!),
        cursor: cursor ?? _cursorHistory.last,
      );
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _checkingAccess = false;
        _loading = false;
        _isAdmin = true;
        _page = page;
      });
    } on AdminApiException catch (error) {
      if (!mounted || requestVersion != _requestVersion) return;
      final denied = error.statusCode == 401 || error.statusCode == 403;
      setState(() {
        _checkingAccess = false;
        _loading = false;
        _isAdmin = denied ? false : _isAdmin;
        _page = denied ? null : _page;
        _errorKey = denied ? 'adminDenied' : 'appointmentsLoadError';
      });
    } on Exception {
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _checkingAccess = false;
        _loading = false;
        _errorKey = 'appointmentsLoadError';
      });
    }
  }

  void _applyFilters() {
    setState(() {
      _cursorHistory
        ..clear()
        ..add(null);
    });
    _load(cursor: null, verifyAccess: false);
  }

  Future<void> _selectDate({required bool start}) async {
    final current = start ? _dateFrom : _dateTo;
    final firstDate = start ? DateTime(2000) : (_dateFrom ?? DateTime(2000));
    final lastDate = start ? (_dateTo ?? DateTime(2100)) : DateTime(2100);
    final selected = await showDatePicker(
      context: context,
      initialDate: current ?? (start ? lastDate : firstDate),
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        _dateFrom = selected;
      } else {
        _dateTo = selected;
      }
    });
    _applyFilters();
  }

  Future<void> _nextPage() async {
    final nextCursor = _page?.nextCursor;
    if (nextCursor == null || _loading) return;
    setState(() => _cursorHistory.add(nextCursor));
    await _load(cursor: nextCursor, verifyAccess: false);
  }

  Future<void> _previousPage() async {
    if (_cursorHistory.length <= 1 || _loading) return;
    setState(() => _cursorHistory.removeLast());
    await _load(cursor: _cursorHistory.last, verifyAccess: false);
  }

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _formatDate(DateTime value) =>
      MaterialLocalizations.of(context).formatMediumDate(value.toLocal());

  void _showNotice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  List<String> _availableStatuses(AdminAppointment appointment) =>
      switch (appointment.status) {
        'pending' => ['confirmed', 'rejected', 'cancelled'],
        'confirmed' => ['completed', 'rejected', 'cancelled'],
        _ => const [],
      };

  Future<void> _moderate(
    AdminAppointment appointment,
    String status,
  ) async {
    final formKey = GlobalKey<FormState>();
    var reasonValue = '';
    final doctorName = appointment.doctorName.isEmpty
        ? appointment.doctorId
        : appointment.doctorName;
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('appointmentChangeTitle')),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('appointmentChangeTarget', arguments: {
                    'doctor': doctorName,
                    'date': _formatDate(appointment.date),
                    'time': appointment.time,
                  }),
                ),
                const SizedBox(height: AppSpacing.x3),
                Text(_t('status_$status')),
                const SizedBox(height: AppSpacing.x2),
                TextFormField(
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  onChanged: (value) => reasonValue = value,
                  decoration: InputDecoration(
                    labelText: _t('appointmentReason'),
                    hintText: _t('appointmentReasonHint'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => (value?.trim().length ?? 0) < 3
                      ? _t('appointmentReasonRequired')
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, reasonValue.trim());
              }
            },
            child: Text(_t('confirm')),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;

    setState(() => _busyAppointmentId = appointment.id);
    try {
      await widget.api.moderateAppointment(
        appointment.id,
        status: status,
        reason: reason,
      );
      if (!mounted) return;
      _showNotice(_t('appointmentUpdated'));
      await _load(verifyAccess: false);
    } on Exception {
      if (mounted) _showNotice(_t('appointmentActionFailed'));
    } finally {
      if (mounted) setState(() => _busyAppointmentId = null);
    }
  }

  Widget _actions(AdminAppointment appointment) {
    final statuses = _availableStatuses(appointment);
    if (statuses.isEmpty) return const SizedBox(width: 48, height: 48);
    return PopupMenuButton<String>(
      tooltip: _t('appointmentActions'),
      enabled: _busyAppointmentId == null,
      onSelected: (status) => _moderate(appointment, status),
      itemBuilder: (context) => [
        for (final status in statuses)
          PopupMenuItem(
            value: status,
            child: Text(_t('status_$status')),
          ),
      ],
      icon: _busyAppointmentId == appointment.id
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.more_vert),
    );
  }

  Widget _filterControls(double width) {
    final fieldWidth = width < 600 ? width : math.min(240.0, width);
    final localizations = MaterialLocalizations.of(context);
    return Wrap(
      spacing: AppSpacing.x3,
      runSpacing: AppSpacing.x3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: fieldWidth,
          child: DropdownButtonFormField<String>(
            initialValue: _statusFilter,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: _t('appointmentStatusFilter'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(
                value: 'all',
                child: Text(_t('allUsers'), overflow: TextOverflow.ellipsis),
              ),
              for (final status in [
                'pending',
                'confirmed',
                'completed',
                'rejected',
                'cancelled',
              ])
                DropdownMenuItem(
                  value: status,
                  child: Text(
                    _t('status_$status'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _statusFilter = value);
              _applyFilters();
            },
          ),
        ),
        SizedBox(
          width: fieldWidth,
          child: TextField(
            controller: _doctorController,
            maxLength: 100,
            onSubmitted: (_) => _applyFilters(),
            decoration: InputDecoration(
              labelText: _t('doctorIdFilter'),
              border: const OutlineInputBorder(),
              isDense: true,
              counterText: '',
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _selectDate(start: true),
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text(
            _dateFrom == null
                ? _t('dateFrom')
                : '${_t('dateFrom')}: ${localizations.formatMediumDate(_dateFrom!)}',
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _selectDate(start: false),
          icon: const Icon(Icons.event_outlined),
          label: Text(
            _dateTo == null
                ? _t('dateTo')
                : '${_t('dateTo')}: ${localizations.formatMediumDate(_dateTo!)}',
          ),
        ),
        if (_dateFrom != null ||
            _dateTo != null ||
            _doctorController.text.isNotEmpty ||
            _statusFilter != 'all')
          TextButton(
            onPressed: () {
              setState(() {
                _statusFilter = 'all';
                _dateFrom = null;
                _dateTo = null;
                _doctorController.clear();
              });
              _applyFilters();
            },
            child: Text(_t('clearAdminFilters')),
          ),
      ],
    );
  }

  Widget _appointmentCard(AdminAppointment appointment) {
    final doctorName = appointment.doctorName.isEmpty
        ? appointment.doctorId
        : appointment.doctorName;
    final clinicName = appointment.clinicName.isEmpty
        ? appointment.clinicId
        : appointment.clinicName;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    doctorName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _actions(appointment),
              ],
            ),
            Text(clinicName),
            if (appointment.city.isNotEmpty) Text(appointment.city),
            const SizedBox(height: AppSpacing.x2),
            Wrap(
              spacing: AppSpacing.x2,
              runSpacing: AppSpacing.x1,
              children: [
                Text(_formatDate(appointment.date)),
                Text(appointment.time),
                Chip(label: Text(_t('status_${appointment.status}'))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  DataColumn _column(String label) => DataColumn(label: Text(label));

  Widget _appointmentTable(List<AdminAppointment> appointments) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            _column(_t('columnDoctor')),
            _column(_t('columnClinic')),
            _column(_t('columnDate')),
            _column(_t('columnTime')),
            _column(_t('columnState')),
            _column(_t('appointmentActions')),
          ],
          rows: [
            for (final appointment in appointments)
              DataRow(
                cells: [
                  DataCell(Text(
                    appointment.doctorName.isEmpty
                        ? appointment.doctorId
                        : appointment.doctorName,
                  )),
                  DataCell(Text(
                    appointment.clinicName.isEmpty
                        ? appointment.clinicId
                        : appointment.clinicName,
                  )),
                  DataCell(Text(_formatDate(appointment.date))),
                  DataCell(Text(appointment.time)),
                  DataCell(Text(_t('status_${appointment.status}'))),
                  DataCell(_actions(appointment)),
                ],
              ),
          ],
        ),
      );

  Widget _errorState(String key) => Center(
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

  Widget _body() {
    if (_checkingAccess) {
      return Center(
        child: Semantics(
          label: _t('loading'),
          child: const CircularProgressIndicator(),
        ),
      );
    }
    if (_errorKey != null) return _errorState(_errorKey!);
    final page = _page;
    if (!_isAdmin || page == null) return _errorState('adminDenied');

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          constraints.maxWidth,
          AppBreakpoints.contentMaxWidth,
        );
        return Center(
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  fit: FlexFit.loose,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * 0.55,
                    ),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.x4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t('appointmentsSubtitle'),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: AppSpacing.x3),
                            _filterControls(width - AppSpacing.x8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (_loading) const LinearProgressIndicator(),
                Expanded(
                  child: page.appointments.isEmpty && !_loading
                      ? Center(child: Text(_t('appointmentsEmpty')))
                      : width >= 800
                          ? SingleChildScrollView(
                              child: _appointmentTable(page.appointments),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.x3,
                              ),
                              itemCount: page.appointments.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: AppSpacing.x2),
                              itemBuilder: (context, index) =>
                                  _appointmentCard(page.appointments[index]),
                            ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.x3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: _t('previousPage'),
                        onPressed: _cursorHistory.length > 1 && !_loading
                            ? _previousPage
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Flexible(
                        child: Text(
                          _t('pageNumber', arguments: {
                            'page': '${_cursorHistory.length}',
                          }),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        tooltip: _t('nextPage'),
                        onPressed: page.nextCursor != null && !_loading
                            ? _nextPage
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_t('appointmentsTitle')),
          actions: [
            if (_isAdmin)
              IconButton(
                tooltip: _t('retry'),
                onPressed: _loading ? null : () => _load(verifyAccess: false),
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        body: _body(),
      );
}
