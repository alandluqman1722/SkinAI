import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../admin/admin_api_service.dart';
import '../admin/admin_appointments_screen.dart';
import '../admin/admin_dashboard_screen.dart';
import '../admin/admin_users_screen.dart';
import '../image_picker_feedback.dart';
import '../localization/app_localizations.dart';
import 'doctor_api_service.dart';
import 'doctor_models.dart';

class DoctorDirectoryScreen extends StatefulWidget {
  const DoctorDirectoryScreen({
    required this.baseUrl,
    required this.idTokenProvider,
    this.api,
    this.adminApi,
    this.tokenChanges,
    super.key,
  });

  final String baseUrl;
  final DoctorIdTokenProvider idTokenProvider;
  final DoctorApiService? api;
  final AdminApiService? adminApi;
  final Stream<void>? tokenChanges;

  @override
  State<DoctorDirectoryScreen> createState() => _DoctorDirectoryScreenState();
}

class _DoctorDirectoryScreenState extends State<DoctorDirectoryScreen>
    with SingleTickerProviderStateMixin {
  late final DoctorApiService _api;
  late final AdminApiService _adminApi;
  late final TabController _tabs;
  StreamSubscription<void>? _adminTokenSubscription;
  final _search = TextEditingController();
  List<DoctorProfile> _doctors = [];
  List<DoctorAppointment> _appointments = [];
  Set<String> _favorites = {};
  String? _error;
  String? _appointmentsError;
  String _city = '';
  String _specialization = '';
  String _clinic = '';
  String _availability = '';
  String _sort = 'rating';
  bool _loading = true;
  bool _appointmentsLoading = false;
  bool _isAdmin = false;
  int _adminAccessRequest = 0;
  bool _favoritesOnly = false;
  int _directoryRequest = 0;
  final Set<String> _favoriteRequests = {};

  AppLocalizations get _l => AppLocalizations.of(context);
  String _t(String key, {Map<String, String> args = const {}}) =>
      _l.text(key, domain: 'doctors', arguments: args);

  @override
  void initState() {
    super.initState();
    _api = widget.api ??
        DoctorApiService(
          baseUrl: widget.baseUrl,
          idTokenProvider: widget.idTokenProvider,
        );
    _adminApi = widget.adminApi ??
        AdminApiService(
          baseUrl: widget.baseUrl,
          idTokenProvider: widget.idTokenProvider,
        );
    _adminTokenSubscription =
        widget.tokenChanges?.listen((_) => _loadAdminAccess());
    _tabs = TabController(length: 2, vsync: this)..addListener(_onTabChanged);
    _loadAdminAccess();
    _loadDirectory();
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTabChanged)
      ..dispose();
    _adminAccessRequest++;
    _adminTokenSubscription?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadAdminAccess() async {
    final request = ++_adminAccessRequest;
    try {
      final isAdmin = await _adminApi.checkAdminStatus();
      if (!mounted || request != _adminAccessRequest) return;
      setState(() => _isAdmin = isAdmin);
    } on AdminApiException catch (error) {
      if (!mounted || request != _adminAccessRequest) return;
      setState(() => _isAdmin = false);
      if (error.statusCode != 401 && error.statusCode != 403) {
        _notice(_t('requestFailed'));
      }
    } on Exception {
      if (!mounted || request != _adminAccessRequest) return;
      setState(() => _isAdmin = false);
      _notice(_t('requestFailed'));
    }
  }

  void _onTabChanged() {
    if (_tabs.index == 1 && !_appointmentsLoading) {
      _loadAppointments();
    }
  }

  Future<void> _loadDirectory() async {
    final requestId = ++_directoryRequest;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait<List<DoctorProfile>>([
        _api.listDoctors(
          search: _search.text,
          city: _city,
          specialization: _specialization,
          clinic: _clinic,
          availableWithinDays:
              _availability.isEmpty ? null : int.parse(_availability),
          sort: _sort,
        ),
        _api.listFavorites(),
      ]);
      if (!mounted || requestId != _directoryRequest) return;
      setState(() {
        _doctors = values[0];
        _favorites = values[1].map((doctor) => doctor.id).toSet();
        _loading = false;
      });
    } on Exception {
      if (!mounted || requestId != _directoryRequest) return;
      setState(() {
        _loading = false;
        _error = _t('loadError');
      });
    }
  }

  Future<void> _loadAppointments() async {
    setState(() {
      _appointmentsLoading = true;
      _appointmentsError = null;
    });
    try {
      final values = await _api.listAppointments();
      if (!mounted) return;
      setState(() {
        _appointments = values;
        _appointmentsLoading = false;
        _appointmentsError = null;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _appointmentsLoading = false;
        _appointmentsError = _t('loadError');
      });
    }
  }

  Future<bool> _toggleFavorite(DoctorProfile doctor) async {
    if (_favoriteRequests.contains(doctor.id)) return false;
    final oldValue = _favorites.contains(doctor.id);
    setState(() {
      _favoriteRequests.add(doctor.id);
      if (oldValue) {
        _favorites.remove(doctor.id);
      } else {
        _favorites.add(doctor.id);
      }
    });
    try {
      await _api.setFavorite(doctor.id, !oldValue);
      if (mounted) {
        setState(() => _favoriteRequests.remove(doctor.id));
      }
      return true;
    } on Exception {
      if (!mounted) return false;
      setState(() {
        _favoriteRequests.remove(doctor.id);
        if (oldValue) {
          _favorites.add(doctor.id);
        } else {
          _favorites.remove(doctor.id);
        }
      });
      _notice(_t('requestFailed'));
      return false;
    }
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _changeFilter(VoidCallback change) {
    setState(change);
    _loadDirectory();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('title')),
        actions: [
          if (_isAdmin)
            IconButton(
              tooltip: _t('adminPanel'),
              onPressed: _openAdmin,
              icon: const Icon(Icons.admin_panel_settings_outlined),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: _t('directory')),
            Tab(text: _t('appointments')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _directory(colors),
          _appointmentList(colors),
        ],
      ),
    );
  }

  Widget _directory(ColorScheme colors) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _emptyState(
        icon: Icons.cloud_off_outlined,
        title: _error!,
        action: FilledButton.tonal(
          onPressed: _loadDirectory,
          child: Text(_t('retry')),
        ),
      );
    }
    final filtered = _doctors
        .where((doctor) => !_favoritesOnly || _favorites.contains(doctor.id))
        .toList();
    final cities = _unique([
      'Erbil',
      'Sulaymaniyah',
      'Duhok',
      'Halabja',
      'Baghdad',
      'Basra',
      'Mosul',
      'Kirkuk',
      'Najaf',
      'Karbala',
      'Other',
      ..._doctors
          .expand((doctor) => doctor.clinics.map((clinic) => clinic.city)),
    ]);
    final specializations =
        _unique(_doctors.expand((doctor) => doctor.specializations));
    final clinics =
        _unique(_doctors.expand((doctor) => doctor.clinics).map((c) => c.name));

    return RefreshIndicator(
      onRefresh: _loadDirectory,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_t('subtitle'),
              style: TextStyle(color: colors.onSurfaceVariant)),
          const SizedBox(height: 16),
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _loadDirectory(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: _t('searchName'),
              suffixIcon: IconButton(
                tooltip: _t('searchName'),
                onPressed: _loadDirectory,
                icon: const Icon(Icons.arrow_forward),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filter(
                label: _t('cityFilter'),
                value: _city,
                allLabel: _t('allCities'),
                values: cities,
                display: _cityName,
                onChanged: (value) => _changeFilter(() => _city = value),
              ),
              _filter(
                label: _t('specializationFilter'),
                value: _specialization,
                allLabel: _t('allSpecializations'),
                values: specializations,
                onChanged: (value) =>
                    _changeFilter(() => _specialization = value),
              ),
              _filter(
                label: _t('clinicFilter'),
                value: _clinic,
                allLabel: _t('allClinics'),
                values: clinics,
                onChanged: (value) => _changeFilter(() => _clinic = value),
              ),
              _filter(
                label: _t('availabilityFilter'),
                value: _availability,
                allLabel: _t('anyAvailability'),
                values: const ['0', '7'],
                display: (value) => value == '0'
                    ? _t('availableToday')
                    : _t('availableThisWeek'),
                onChanged: (value) =>
                    _changeFilter(() => _availability = value),
              ),
              _filter(
                label: _t('sortByRating'),
                value: _sort,
                allLabel: _t('sortByRating'),
                values: const ['rating', 'experience'],
                includeAll: false,
                display: (value) => value == 'rating'
                    ? _t('sortByRating')
                    : _t('sortByExperience'),
                onChanged: (value) => _changeFilter(() => _sort = value),
              ),
              FilterChip(
                selected: _favoritesOnly,
                avatar: const Icon(Icons.favorite_border, size: 18),
                label: Text(_t('favoritesOnly')),
                onSelected: (value) => setState(() => _favoritesOnly = value),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (filtered.isEmpty)
            _emptyState(
              icon: Icons.medical_services_outlined,
              title: _doctors.isEmpty ? _t('noDoctors') : _t('noMatches'),
              subtitle: _doctors.isEmpty ? _t('noDoctorsSubtitle') : null,
            )
          else
            for (final doctor in filtered) ...[
              _doctorCard(doctor),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  Widget _filter({
    required String label,
    required String value,
    required String allLabel,
    required List<String> values,
    required ValueChanged<String> onChanged,
    String Function(String value)? display,
    bool includeAll = true,
  }) {
    final entries = <DropdownMenuItem<String>>[
      if (includeAll) DropdownMenuItem(value: '', child: Text(allLabel)),
      for (final item in values)
        DropdownMenuItem<String>(
          value: item,
          child: Text(display?.call(item) ?? item.toString()),
        ),
    ];
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 240),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
        items: entries,
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }

  Widget _doctorCard(DoctorProfile doctor) {
    final colors = Theme.of(context).colorScheme;
    final clinicText = doctor.clinics
        .map((clinic) => '${clinic.name} · ${_cityName(clinic.city)}')
        .join('\n');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _doctorAvatar(doctor, 66),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doctor.fullName,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (doctor.verified) ...[
                        const SizedBox(height: 4),
                        Chip(
                          avatar: Icon(Icons.verified,
                              color: colors.primary, size: 18),
                          label: Text(_t('verifiedDoctor')),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                      ],
                      Text(
                        doctor.specializations.join(' · '),
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: _t(_favorites.contains(doctor.id)
                      ? 'unfavorite'
                      : 'favorite'),
                  onPressed: () {
                    _toggleFavorite(doctor);
                  },
                  icon: Icon(
                    _favorites.contains(doctor.id)
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: _favorites.contains(doctor.id) ? colors.error : null,
                  ),
                ),
              ],
            ),
            if (clinicText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(clinicText,
                  style: TextStyle(color: colors.onSurfaceVariant)),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (doctor.experienceYears != null)
                  Text(_t('experienceYears',
                      args: {'count': '${doctor.experienceYears}'})),
                if (doctor.averageRating != null)
                  Text(
                    '★ ${doctor.averageRating!.toStringAsFixed(1)}  '
                    '(${_t('reviewsCount', args: {
                          'count': '${doctor.reviewCount}'
                        })})',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton(
                  onPressed: () => _openProfile(doctor),
                  child: Text(_t('viewProfile')),
                ),
                FilledButton(
                  onPressed: () => _openBooking(doctor),
                  child: Text(_t('bookAppointment')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _doctorAvatar(DoctorProfile doctor, double size) {
    return _avatar(
      doctor,
      _api,
      size,
    );
  }

  Future<void> _openProfile(DoctorProfile doctor) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DoctorProfileScreen(
          api: _api,
          doctor: doctor,
          isFavorite: _favorites.contains(doctor.id),
          onFavoriteChanged: () => _toggleFavorite(doctor),
          onBook: () => _openBooking(doctor),
          onNotice: _notice,
        ),
      ),
    );
    _loadDirectory();
  }

  Future<void> _openBooking(DoctorProfile doctor) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AppointmentBookingSheet(
        api: _api,
        doctor: doctor,
        onBooked: () {
          _notice(_t('appointmentBooked'));
          if (_tabs.index == 1) _loadAppointments();
        },
        localize: _t,
      ),
    );
  }

  Widget _appointmentList(ColorScheme colors) {
    if (_appointmentsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_appointments.isEmpty) {
      return _emptyState(
        icon: Icons.event_note_outlined,
        title: _appointmentsError ?? _t('noAppointments'),
        action: _appointmentsError == null
            ? null
            : FilledButton.tonal(
                onPressed: _loadAppointments,
                child: Text(_t('retry')),
              ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAppointments,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _appointments.length,
        itemBuilder: (context, index) {
          final appointment = _appointments[index];
          return Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: Text(appointment.doctorName),
                    subtitle: Text(
                      '${appointment.clinicName} · ${_cityName(appointment.city)}\n'
                      '${appointment.date} · ${appointment.time} · '
                      '${_statusName(appointment.status)}',
                    ),
                    isThreeLine: true,
                  ),
                  Wrap(
                    children: [
                      if (appointment.status == 'pending' ||
                          appointment.status == 'confirmed')
                        TextButton.icon(
                          onPressed: () => _cancelAppointment(appointment),
                          icon: const Icon(Icons.cancel_outlined),
                          label: Text(_t('cancelAppointment')),
                        ),
                      if (appointment.status == 'completed')
                        TextButton.icon(
                          onPressed: () => _reviewAppointment(appointment),
                          icon: const Icon(Icons.rate_review_outlined),
                          label: Text(_t('submitReview')),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _cancelAppointment(DoctorAppointment appointment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('cancelAppointment')),
        content: Text(_t('cancelAppointmentConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('cancelAppointment')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.cancelAppointment(appointment.id);
      _loadAppointments();
    } on Exception {
      _notice(_t('requestFailed'));
    }
  }

  Future<void> _reviewAppointment(DoctorAppointment appointment) async {
    final comment = TextEditingController();
    var rating = 5;
    final result = await showDialog<(int, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_t('submitReview')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_t('yourRating')),
              Text(
                _t('reviewPrivacyNote'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Wrap(
                children: [
                  for (var value = 1; value <= 5; value++)
                    IconButton(
                      tooltip: '$value',
                      onPressed: () => setDialogState(() => rating = value),
                      icon: Icon(
                          value <= rating ? Icons.star : Icons.star_border),
                    ),
                ],
              ),
              TextField(
                controller: comment,
                maxLines: 4,
                decoration: InputDecoration(labelText: _t('reviewComment')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_t('cancel')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, (rating, comment.text.trim())),
              child: Text(_t('submitReview')),
            ),
          ],
        ),
      ),
    );
    comment.dispose();
    if (result == null || result.$2.isEmpty) return;
    try {
      await _api.submitReview(
        appointmentId: appointment.id,
        rating: result.$1,
        comment: result.$2,
      );
      _notice(_t('reviewPending'));
      _loadAppointments();
    } on Exception {
      _notice(_t('requestFailed'));
    }
  }

  Future<void> _openAdmin() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AdminDashboardScreen(
          api: _adminApi,
          tokenChanges: widget.tokenChanges,
          doctorManagementBuilder: (_) => DoctorAdminScreen(
            api: _api,
            localize: _t,
            onNotice: _notice,
          ),
          userManagementBuilder: (_) => AdminUsersScreen(
            api: _adminApi,
            tokenChanges: widget.tokenChanges,
          ),
          appointmentManagementBuilder: (_) => AdminAppointmentsScreen(
            api: _adminApi,
            tokenChanges: widget.tokenChanges,
          ),
        ),
      ),
    );
    _loadDirectory();
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? action,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: colors.primary),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action],
          ],
        ),
      ),
    );
  }

  List<String> _unique(Iterable<String> values) => values
      .map((value) => value.trim())
      .where((v) => v.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  String _cityName(String city) {
    const keys = {
      'Erbil': 'cityErbil',
      'Sulaymaniyah': 'citySulaymaniyah',
      'Duhok': 'cityDuhok',
      'Halabja': 'cityHalabja',
      'Baghdad': 'cityBaghdad',
      'Basra': 'cityBasra',
      'Mosul': 'cityMosul',
      'Kirkuk': 'cityKirkuk',
      'Najaf': 'cityNajaf',
      'Karbala': 'cityKarbala',
      'Other': 'cityOther',
    };
    final key = keys[city];
    return key == null ? city : _t(key);
  }

  String _statusName(String value) {
    final key = switch (value) {
      'pending' => 'statusPending',
      'confirmed' => 'statusConfirmed',
      'rejected' => 'statusRejected',
      'cancelled' => 'statusCancelled',
      'completed' => 'statusCompleted',
      _ => 'statusPending',
    };
    return _t(key);
  }
}

class DoctorProfileScreen extends StatefulWidget {
  const DoctorProfileScreen({
    required this.api,
    required this.doctor,
    required this.isFavorite,
    required this.onFavoriteChanged,
    required this.onBook,
    required this.onNotice,
    super.key,
  });

  final DoctorApiService api;
  final DoctorProfile doctor;
  final bool isFavorite;
  final Future<bool> Function() onFavoriteChanged;
  final VoidCallback onBook;
  final ValueChanged<String> onNotice;

  @override
  State<DoctorProfileScreen> createState() => _DoctorProfileScreenState();
}

class _DoctorProfileScreenState extends State<DoctorProfileScreen> {
  late Future<List<DoctorReview>> _reviews;
  bool _favorite = false;

  AppLocalizations get _l => AppLocalizations.of(context);
  String _t(String key, {Map<String, String> args = const {}}) =>
      _l.text(key, domain: 'doctors', arguments: args);

  @override
  void initState() {
    super.initState();
    _favorite = widget.isFavorite;
    _reviews = widget.api.listReviews(widget.doctor.id);
  }

  @override
  Widget build(BuildContext context) {
    final doctor = widget.doctor;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('profile')),
        actions: [
          IconButton(
            tooltip: _t(_favorite ? 'unfavorite' : 'favorite'),
            onPressed: () async {
              final previous = _favorite;
              setState(() => _favorite = !previous);
              final updated = await widget.onFavoriteChanged();
              if (!updated && mounted) {
                setState(() => _favorite = previous);
              }
            },
            icon: Icon(_favorite ? Icons.favorite : Icons.favorite_border),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: widget.onBook,
          child: Text(_t('bookAppointment')),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Center(child: _avatar(doctor, widget.api, 112)),
          const SizedBox(height: 16),
          Text(
            doctor.fullName,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          Center(
            child: Chip(
              avatar: Icon(
                doctor.verified ? Icons.verified : Icons.info_outline,
                color: colors.primary,
                size: 18,
              ),
              label: Text(
                _t(doctor.verified ? 'verifiedDoctor' : 'unverifiedDoctor'),
              ),
            ),
          ),
          if (doctor.averageRating != null)
            Text(
              '★ ${doctor.averageRating!.toStringAsFixed(1)} · '
              '${_t('reviewsCount', args: {'count': '${doctor.reviewCount}'})}',
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 20),
          _section(_t('specializations'), doctor.specializations.join(' · ')),
          if (doctor.verified && doctor.qualifications.isNotEmpty)
            _section(_t('qualifications'), doctor.qualifications.join('\n')),
          if (doctor.verified && doctor.experienceYears != null)
            _section(
              _t('experience'),
              _t('experienceYears',
                  args: {'count': '${doctor.experienceYears}'}),
            ),
          if (doctor.biography.isNotEmpty)
            _section(_t('aboutDoctor'), doctor.biography),
          if (doctor.languages.isNotEmpty)
            _section(_t('languages'), doctor.languages.join(' · ')),
          const SizedBox(height: 8),
          Text(_t('clinics'), style: Theme.of(context).textTheme.titleMedium),
          for (final clinic in doctor.clinics) _clinicCard(clinic),
          const SizedBox(height: 16),
          Text(_t('reviews'), style: Theme.of(context).textTheme.titleMedium),
          FutureBuilder<List<DoctorReview>>(
            future: _reviews,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(_t('loadError')),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final reviews = snapshot.data ?? const <DoctorReview>[];
              if (reviews.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(_t('noReviews')),
                );
              }
              return Column(
                children: [
                  for (final review in reviews)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.star_outline),
                        title: Text('★ ${review.rating}'),
                        subtitle: Text(review.comment),
                        trailing: IconButton(
                          tooltip: _t('reportReview'),
                          icon: const Icon(Icons.flag_outlined),
                          onPressed: () => _reportReview(review),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _section(String title, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(value),
          ],
        ),
      );

  Widget _clinicCard(DoctorClinic clinic) {
    final color = Theme.of(context).colorScheme;
    final hours = clinic.weeklySchedule
        .map((rule) => '${_weekday(rule.weekday)}: ${rule.times.join(', ')}')
        .join('\n');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(clinic.name, style: Theme.of(context).textTheme.titleSmall),
            Text('${_cityName(clinic.city)} · ${clinic.address}'),
            if (hours.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_t('workingHours')),
              Text(hours, style: TextStyle(color: color.onSurfaceVariant)),
            ],
            if (clinic.phone != null || clinic.website != null)
              Wrap(
                spacing: 8,
                children: [
                  if (clinic.phone != null)
                    TextButton.icon(
                      onPressed: () => _launch('tel:${clinic.phone}'),
                      icon: const Icon(Icons.phone_outlined),
                      label: Text(clinic.phone!),
                    ),
                  if (clinic.website != null)
                    TextButton.icon(
                      onPressed: () => _launch(clinic.website!),
                      icon: const Icon(Icons.language),
                      label: Text(_t('contact')),
                    ),
                ],
              ),
            if (clinic.latitude != null && clinic.longitude != null)
              TextButton.icon(
                onPressed: () => _launch(
                  'https://www.google.com/maps/search/?api=1&query='
                  '${clinic.latitude},${clinic.longitude}',
                ),
                icon: const Icon(Icons.directions_outlined),
                label: Text(_t('openDirections')),
              )
            else
              Text(_t('noCoordinates')),
          ],
        ),
      ),
    );
  }

  Future<void> _reportReview(DoctorReview review) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('reportReview')),
        content: TextField(
          controller: reasonController,
          decoration: InputDecoration(labelText: _t('reportReason')),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, reasonController.text.trim()),
            child: Text(_t('reportReview')),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null || reason.isEmpty) return;
    try {
      await widget.api.reportReview(
        doctorId: widget.doctor.id,
        reviewId: review.id,
        reason: reason,
      );
      widget.onNotice(_t('reportSubmitted'));
    } on Exception {
      widget.onNotice(_t('requestFailed'));
    }
  }

  String _weekday(int weekday) => _t([
        'monday',
        'tuesday',
        'wednesday',
        'thursday',
        'friday',
        'saturday',
        'sunday',
      ][weekday.clamp(0, 6)]);

  String _cityName(String city) {
    const keys = {
      'Erbil': 'cityErbil',
      'Sulaymaniyah': 'citySulaymaniyah',
      'Duhok': 'cityDuhok',
      'Halabja': 'cityHalabja',
      'Baghdad': 'cityBaghdad',
      'Basra': 'cityBasra',
      'Mosul': 'cityMosul',
      'Kirkuk': 'cityKirkuk',
      'Najaf': 'cityNajaf',
      'Karbala': 'cityKarbala',
      'Other': 'cityOther',
    };
    final key = keys[city];
    return key == null ? city : _t(key);
  }

  Future<void> _launch(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      widget.onNotice(_t('requestFailed'));
    }
  }
}

Widget _avatar(DoctorProfile doctor, DoctorApiService api, double size) {
  final url = doctor.photoUrl;
  final uri = url == null ? null : Uri.parse(api.baseUrl).resolve(url);
  return Semantics(
    image: true,
    label: doctor.fullName,
    child: CircleAvatar(
      radius: size / 2,
      child: uri == null
          ? const Icon(Icons.person_outline)
          : ClipOval(
              child: Image.network(
                uri.toString(),
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.person_outline),
              ),
            ),
    ),
  );
}

class _AppointmentBookingSheet extends StatefulWidget {
  const _AppointmentBookingSheet({
    required this.api,
    required this.doctor,
    required this.onBooked,
    required this.localize,
  });

  final DoctorApiService api;
  final DoctorProfile doctor;
  final VoidCallback onBooked;
  final String Function(String, {Map<String, String> args}) localize;

  @override
  State<_AppointmentBookingSheet> createState() =>
      _AppointmentBookingSheetState();
}

class _AppointmentBookingSheetState extends State<_AppointmentBookingSheet> {
  DoctorClinic? _clinic;
  DateTime? _date;
  List<String> _times = [];
  String? _time;
  bool _loading = false;
  bool _submitting = false;
  int _availabilityRequest = 0;

  String t(String key, {Map<String, String> args = const {}}) =>
      widget.localize(key, args: args);

  @override
  Widget build(BuildContext context) {
    final clinics = widget.doctor.clinics;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('appointmentRequest'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<DoctorClinic>(
                initialValue: _clinic,
                decoration: InputDecoration(labelText: t('chooseClinic')),
                items: [
                  for (final clinic in clinics)
                    DropdownMenuItem(
                      value: clinic,
                      child: Text('${clinic.name} · ${clinic.city}'),
                    ),
                ],
                onChanged: (clinic) {
                  setState(() {
                    _clinic = clinic;
                    _date = null;
                    _times = [];
                    _time = null;
                    _loading = false;
                    _availabilityRequest++;
                  });
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _clinic == null ? null : _chooseDate,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(_date == null
                    ? t('chooseDate')
                    : '${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-'
                        '${_date!.day.toString().padLeft(2, '0')}'),
              ),
              if (_loading) const LinearProgressIndicator(),
              if (_date != null && !_loading && _times.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(t('noTimes')),
                ),
              if (_times.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _time,
                  decoration: InputDecoration(labelText: t('chooseTime')),
                  items: [
                    for (final time in _times)
                      DropdownMenuItem(value: time, child: Text(time)),
                  ],
                  onChanged: (value) => setState(() => _time = value),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _time == null || _submitting ? null : _book,
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(t('bookAppointment')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year, now.month, now.day + 30),
    );
    if (selected == null || _clinic == null) return;
    setState(() {
      _date = selected;
      _time = null;
      _times = [];
      _loading = true;
    });
    final requestId = ++_availabilityRequest;
    try {
      final values = await widget.api.availableTimes(
        doctorId: widget.doctor.id,
        clinicId: _clinic!.id,
        date: selected,
      );
      if (!mounted || requestId != _availabilityRequest) return;
      setState(() {
        _times = values;
        _loading = false;
      });
    } on Exception {
      if (!mounted || requestId != _availabilityRequest) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('requestFailed'))),
      );
    }
  }

  Future<void> _book() async {
    final clinic = _clinic;
    final date = _date;
    final time = _time;
    if (clinic == null || date == null || time == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('appointmentRequest')),
        content: Text(
          t('appointmentConfirm', args: {
            'doctor': widget.doctor.fullName,
            'clinic': clinic.name,
            'date': '${date.year}-${date.month}-${date.day}',
            'time': time,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('bookAppointment')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _submitting = true);
    try {
      await widget.api.bookAppointment(
        doctorId: widget.doctor.id,
        clinicId: clinic.id,
        date: date,
        time: time,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onBooked();
    } on Exception {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('requestFailed'))),
      );
    }
  }
}

class DoctorAdminScreen extends StatefulWidget {
  const DoctorAdminScreen({
    required this.api,
    required this.localize,
    required this.onNotice,
    super.key,
  });

  final DoctorApiService api;
  final String Function(String, {Map<String, String> args}) localize;
  final ValueChanged<String> onNotice;

  @override
  State<DoctorAdminScreen> createState() => _DoctorAdminScreenState();
}

class _DoctorAdminScreenState extends State<DoctorAdminScreen> {
  List<DoctorProfile> _doctors = [];
  List<DoctorAppointment> _appointments = [];
  List<DoctorReview> _reviews = [];
  List<DoctorAdminReport> _reports = [];
  bool _loading = true;
  String? _error;
  String _section = 'doctors';

  String t(String key, {Map<String, String> args = const {}}) =>
      widget.localize(key, args: args);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        widget.api.listAdminDoctors(),
        widget.api.listAdminAppointments(),
        widget.api.listAdminReviews(),
        widget.api.listAdminReports(),
      ]);
      if (!mounted) return;
      setState(() {
        _doctors = values[0] as List<DoctorProfile>;
        _appointments = values[1] as List<DoctorAppointment>;
        _reviews = values[2] as List<DoctorReview>;
        _reports = values[3] as List<DoctorAdminReport>;
        _loading = false;
      });
    } on DoctorApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.statusCode == 403 ? t('adminOnly') : t('loadError');
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = t('loadError');
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(t('adminPanel')),
          actions: [
            IconButton(
              tooltip: t('retry'),
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton.tonal(
                            onPressed: _load,
                            child: Text(t('retry')),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final entry in [
                              ('doctors', t('directory')),
                              ('appointments', t('adminAppointments')),
                              ('reviews', t('adminReviews')),
                              ('reports', t('adminReports')),
                            ])
                              Padding(
                                padding: const EdgeInsets.all(4),
                                child: ChoiceChip(
                                  label: Text(entry.$2),
                                  selected: _section == entry.$1,
                                  onSelected: (_) =>
                                      setState(() => _section = entry.$1),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(child: _content()),
                    ],
                  ),
        floatingActionButton:
            !_loading && _error == null && _section == 'doctors'
                ? FloatingActionButton.extended(
                    onPressed: () => _editDoctor(),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: Text(t('addDoctor')),
                  )
                : null,
      );

  Widget _content() {
    if (_section == 'doctors') {
      if (_doctors.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('noDoctors')),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _editDoctor(),
                icon: const Icon(Icons.add),
                label: Text(t('addDoctor')),
              ),
            ],
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _doctors.length,
        itemBuilder: (context, index) {
          final doctor = _doctors[index];
          return Card(
            child: ListTile(
              leading: _avatar(doctor, widget.api, 48),
              title: Text(doctor.fullName),
              subtitle: Text(
                '${doctor.verificationStatus} · ${doctor.publicationStatus}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') _editDoctor(doctor);
                  if (value == 'documents') _verification(doctor);
                  if (value == 'verify') {
                    _setVerification(doctor, 'approved');
                  }
                  if (value == 'reject') {
                    _setVerification(doctor, 'rejected');
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'edit', child: Text(t('editDoctor'))),
                  PopupMenuItem(
                    value: 'documents',
                    child: Text(t('verificationDocuments')),
                  ),
                  PopupMenuItem(
                    value: 'verify',
                    child: Text(t('approveVerification')),
                  ),
                  PopupMenuItem(
                    value: 'reject',
                    child: Text(t('rejectVerification')),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
    if (_section == 'appointments') {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final appointment in _appointments)
            Card(
              child: ListTile(
                title: Text(appointment.doctorName),
                subtitle: Text(
                  '${appointment.patientName ?? ''}\n'
                  '${appointment.clinicName} · ${appointment.date} · '
                  '${appointment.time} · ${_status(appointment.status)}',
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (value) =>
                      _moderateAppointment(appointment, value),
                  itemBuilder: (context) => [
                    for (final status in [
                      'confirmed',
                      'rejected',
                      'completed',
                      'cancelled',
                    ])
                      PopupMenuItem(
                        value: status,
                        child: Text(_status(status)),
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    if (_section == 'reviews') {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final review in _reviews)
            Card(
              child: ListTile(
                title: Text('★ ${review.rating} · ${review.id}'),
                subtitle: Text(review.comment),
                trailing: PopupMenuButton<String>(
                  onSelected: (status) => _moderateReview(review, status),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'approved',
                      child: Text(t('approve')),
                    ),
                    PopupMenuItem(
                      value: 'rejected',
                      child: Text(t('reject')),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final report in _reports)
          Card(
            child: ListTile(
              title: Text(report.reason),
              subtitle: Text('${report.doctorId} · ${report.reviewId}'),
              trailing: PopupMenuButton<String>(
                onSelected: (value) => _moderateReport(report, value),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'reviewed',
                    child: Text(t('markReviewed')),
                  ),
                  PopupMenuItem(value: 'dismissed', child: Text(t('dismiss'))),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _editDoctor([DoctorProfile? initial]) async {
    final name = TextEditingController(text: initial?.fullName);
    final specializations =
        TextEditingController(text: initial?.specializations.join('\n'));
    final qualifications =
        TextEditingController(text: initial?.qualifications.join('\n'));
    final experience =
        TextEditingController(text: initial?.experienceYears?.toString());
    final biography = TextEditingController(text: initial?.biography);
    final languages =
        TextEditingController(text: initial?.languages.join('\n'));
    final clinics = initial?.clinics.toList() ?? <DoctorClinic>[];
    var publicationStatus =
        initial?.publicationStatus == 'published' ? 'published' : 'draft';
    XFile? photoFile;
    XFile? documentFile;
    final formKey = GlobalKey<FormState>();

    Future<void> editClinicDialog({
      DoctorClinic? existing,
      int? index,
    }) async {
      final clinicName = TextEditingController(text: existing?.name);
      final city = TextEditingController(text: existing?.city);
      final address = TextEditingController(text: existing?.address);
      final latitude =
          TextEditingController(text: existing?.latitude?.toString());
      final longitude =
          TextEditingController(text: existing?.longitude?.toString());
      final phone = TextEditingController(text: existing?.phone);
      final website = TextEditingController(text: existing?.website);
      final scheduleByDay = <int, TextEditingController>{
        for (final rule in existing?.weeklySchedule ?? const [])
          rule.weekday: TextEditingController(text: rule.times.join(', ')),
      };
      final selectedDays = scheduleByDay.keys.toSet();
      final clinicForm = GlobalKey<FormState>();
      final savedClinic = await showDialog<DoctorClinic>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setClinicState) => AlertDialog(
            title: Text(t(existing == null ? 'addClinic' : 'editClinic')),
            content: SizedBox(
              width: 520,
              child: Form(
                key: clinicForm,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _field(clinicName, t('clinicName'), required: true),
                      _field(city, t('city'), required: true),
                      _field(address, t('address'), required: true),
                      _field(latitude, t('latitude')),
                      _field(longitude, t('longitude')),
                      _field(phone, t('phone')),
                      _field(website, t('website')),
                      const SizedBox(height: 8),
                      Text(t('workingDays')),
                      for (var day = 0; day < 7; day++)
                        Column(
                          children: [
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(_weekday(day)),
                              value: selectedDays.contains(day),
                              onChanged: (selected) {
                                setClinicState(() {
                                  if (selected == true) {
                                    selectedDays.add(day);
                                    scheduleByDay.putIfAbsent(
                                      day,
                                      () => TextEditingController(
                                        text: '09:00, 13:00',
                                      ),
                                    );
                                  } else {
                                    selectedDays.remove(day);
                                    scheduleByDay.remove(day)?.dispose();
                                  }
                                });
                              },
                            ),
                            if (selectedDays.contains(day))
                              _field(
                                scheduleByDay[day]!,
                                t('availableTimes'),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('cancel')),
              ),
              FilledButton(
                onPressed: () {
                  if (clinicForm.currentState?.validate() != true) return;
                  final rawLatitude = latitude.text.trim();
                  final rawLongitude = longitude.text.trim();
                  if (rawLatitude.isNotEmpty != rawLongitude.isNotEmpty ||
                      (rawLatitude.isNotEmpty &&
                          (double.tryParse(rawLatitude) == null ||
                              double.tryParse(rawLongitude) == null))) {
                    widget.onNotice(t('invalidCoordinates'));
                    return;
                  }
                  final rules = <DoctorAvailabilityRule>[];
                  for (final day in selectedDays) {
                    final rawTimes = scheduleByDay[day]!
                        .text
                        .split(',')
                        .map((item) => item.trim())
                        .where((item) => item.isNotEmpty)
                        .toList();
                    if (rawTimes.any(
                      (time) => !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$')
                          .hasMatch(time),
                    )) {
                      widget.onNotice(t('requestFailed'));
                      return;
                    }
                    rules.add(
                      DoctorAvailabilityRule(
                        weekday: day,
                        times: rawTimes,
                      ),
                    );
                  }
                  Navigator.pop(
                    context,
                    DoctorClinic(
                      id: existing?.id ?? '',
                      name: clinicName.text.trim(),
                      city: city.text.trim(),
                      address: address.text.trim(),
                      latitude: rawLatitude.isEmpty
                          ? null
                          : double.parse(rawLatitude),
                      longitude: rawLongitude.isEmpty
                          ? null
                          : double.parse(rawLongitude),
                      phone:
                          phone.text.trim().isEmpty ? null : phone.text.trim(),
                      website: website.text.trim().isEmpty
                          ? null
                          : website.text.trim(),
                      weeklySchedule: rules,
                    ),
                  );
                },
                child: Text(t('save')),
              ),
            ],
          ),
        ),
      );
      for (final controller in [
        clinicName,
        city,
        address,
        latitude,
        longitude,
        phone,
        website,
        ...scheduleByDay.values,
      ]) {
        controller.dispose();
      }
      if (savedClinic != null) {
        if (index == null) {
          clinics.add(savedClinic);
        } else {
          clinics[index] = savedClinic;
        }
      }
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(initial == null ? t('addDoctor') : t('editDoctor')),
          content: SizedBox(
            width: 560,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _field(name, t('fullName'), required: true),
                    _field(specializations, t('specializationsField'),
                        required: true, lines: 3),
                    _field(qualifications, t('qualificationsField'), lines: 3),
                    _field(
                      experience,
                      t('experienceField'),
                      keyboard: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return null;
                        final years = int.tryParse(value.trim());
                        return years == null || years < 0 || years > 80
                            ? t('invalidExperience')
                            : null;
                      },
                    ),
                    _field(biography, t('biography'), lines: 3),
                    _field(languages, t('languagesField'), lines: 2),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () async {
                          await editClinicDialog();
                          setDialogState(() {});
                        },
                        icon: const Icon(Icons.add_business_outlined),
                        label: Text(t('addClinic')),
                      ),
                    ),
                    for (var index = 0; index < clinics.length; index++)
                      ListTile(
                        dense: true,
                        title: Text(clinics[index].name),
                        subtitle: Text(
                          '${clinics[index].city} · ${clinics[index].address}',
                        ),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              tooltip: t('editClinic'),
                              onPressed: () async {
                                await editClinicDialog(
                                  existing: clinics[index],
                                  index: index,
                                );
                                setDialogState(() {});
                              },
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: t('removeClinic'),
                              onPressed: () => setDialogState(
                                () => clinics.removeAt(index),
                              ),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                          ],
                        ),
                      ),
                    DropdownButtonFormField<String>(
                      initialValue: publicationStatus,
                      decoration:
                          InputDecoration(labelText: t('publishProfile')),
                      items: [
                        DropdownMenuItem(
                            value: 'draft', child: Text(t('draftProfile'))),
                        DropdownMenuItem(
                            value: 'published',
                            child: Text(t('publishProfile'))),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          publicationStatus = value;
                          setDialogState(() {});
                        }
                      },
                    ),
                    Wrap(
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            try {
                              final selected = await ImagePicker().pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 1200,
                                imageQuality: 88,
                              );
                              if (selected != null) photoFile = selected;
                            } on Object catch (error) {
                              if (context.mounted) {
                                showImagePickerFailure(
                                  context,
                                  error,
                                  translate: t,
                                );
                              }
                            }
                            if (context.mounted) setDialogState(() {});
                          },
                          icon: const Icon(Icons.photo_camera_back_outlined),
                          label: Text(photoFile?.name ?? t('uploadPhoto')),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            try {
                              final selected = await ImagePicker().pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 1800,
                                imageQuality: 92,
                              );
                              if (selected != null) documentFile = selected;
                            } on Object catch (error) {
                              if (context.mounted) {
                                showImagePickerFailure(
                                  context,
                                  error,
                                  translate: t,
                                );
                              }
                            }
                            if (context.mounted) setDialogState(() {});
                          },
                          icon: const Icon(Icons.upload_file_outlined),
                          label:
                              Text(documentFile?.name ?? t('uploadDocument')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true ||
                    clinics.isEmpty) {
                  return;
                }
                Navigator.pop(context, true);
              },
              child: Text(t('save')),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      try {
        final doctor = await widget.api.saveDoctor(
          DoctorProfile(
            id: initial?.id ?? '',
            fullName: name.text.trim(),
            specializations: _lines(specializations.text),
            qualifications: _lines(qualifications.text),
            experienceYears: int.tryParse(experience.text),
            biography: biography.text.trim(),
            languages: _lines(languages.text),
            clinics: clinics,
            verified: initial?.verified ?? false,
            publicationStatus: publicationStatus,
          ),
          isNew: initial == null,
        );
        if (photoFile != null) {
          await widget.api.uploadDoctorImage(doctor.id, photoFile!);
        }
        if (documentFile != null) {
          await widget.api.uploadVerificationDocument(doctor.id, documentFile!);
        }
        widget.onNotice(t('saved'));
        _load();
      } on Exception {
        widget.onNotice(t('requestFailed'));
      }
    }
    for (final controller in [
      name,
      specializations,
      qualifications,
      experience,
      biography,
      languages,
    ]) {
      controller.dispose();
    }
  }

  Future<void> _verification(DoctorProfile doctor) async {
    if (doctor.verificationDocuments.isEmpty) {
      widget.onNotice(t('noVerificationDocuments'));
      return;
    }
    final document = doctor.verificationDocuments.first;
    try {
      final bytes = await widget.api.getVerificationDocument(
        doctorId: doctor.id,
        documentId: document.id,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('verificationDocuments')),
          content: SizedBox(
            width: 520,
            child: Image.memory(Uint8List.fromList(bytes), fit: BoxFit.contain),
          ),
        ),
      );
    } on Exception {
      widget.onNotice(t('requestFailed'));
    }
  }

  Future<void> _setVerification(DoctorProfile doctor, String status) async {
    try {
      await widget.api.setVerification(doctor.id, status: status);
      _load();
    } on Exception {
      widget.onNotice(t('requestFailed'));
    }
  }

  Future<void> _moderateAppointment(
    DoctorAppointment appointment,
    String status,
  ) async {
    try {
      await widget.api.moderateAppointment(appointment.id, status);
      _load();
    } on Exception {
      widget.onNotice(t('requestFailed'));
    }
  }

  Future<void> _moderateReview(DoctorReview review, String status) async {
    try {
      await widget.api.moderateReview(review.id, status);
      _load();
    } on Exception {
      widget.onNotice(t('requestFailed'));
    }
  }

  Future<void> _moderateReport(DoctorAdminReport report, String status) async {
    try {
      await widget.api.moderateReport(report.id, status);
      _load();
    } on Exception {
      widget.onNotice(t('requestFailed'));
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    int lines = 1,
    TextInputType? keyboard,
    String? Function(String?)? validator,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: controller,
          maxLines: lines,
          keyboardType: keyboard,
          validator: validator ??
              (required
                  ? (value) => value == null || value.trim().isEmpty
                      ? t('requiredField')
                      : null
                  : null),
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  List<String> _lines(String value) => value
      .split('\n')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  String _weekday(int weekday) => t([
        'monday',
        'tuesday',
        'wednesday',
        'thursday',
        'friday',
        'saturday',
        'sunday',
      ][weekday]);

  String _status(String status) => t(switch (status) {
        'confirmed' => 'statusConfirmed',
        'rejected' => 'statusRejected',
        'cancelled' => 'statusCancelled',
        'completed' => 'statusCompleted',
        _ => 'statusPending',
      });
}
