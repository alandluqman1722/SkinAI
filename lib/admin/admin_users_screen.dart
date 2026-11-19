import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:skin_ai/design/app_design_system.dart';
import 'package:skin_ai/localization/app_localizations.dart';

import 'admin_api_service.dart';
import 'admin_models.dart';

typedef AdminPasswordResetSender = Future<void> Function(String email);

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({
    required this.api,
    this.tokenChanges,
    this.passwordResetSender,
    super.key,
  });

  final AdminApiService api;
  final Stream<void>? tokenChanges;
  final AdminPasswordResetSender? passwordResetSender;

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _searchController = TextEditingController();
  final List<String?> _cursorHistory = [null];
  StreamSubscription<void>? _tokenSubscription;
  AdminUsersPage? _page;
  bool _checkingAccess = true;
  bool _isAdmin = false;
  bool _loading = false;
  String? _errorKey;
  String _blockedFilter = 'all';
  String _disabledFilter = 'all';
  String _sortColumn = 'created';
  bool _sortAscending = false;
  String? _busyUserUid;
  Timer? _searchDebounce;
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
    _searchDebounce?.cancel();
    _searchController.dispose();
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
      final page = await widget.api.loadUsers(
        search: _searchController.text.trim(),
        cursor: cursor ?? _cursorHistory.last,
        blocked: switch (_blockedFilter) {
          'blocked' => true,
          'unblocked' => false,
          _ => null,
        },
        disabled: switch (_disabledFilter) {
          'disabled' => true,
          'enabled' => false,
          _ => null,
        },
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
        _errorKey = denied ? 'adminDenied' : 'usersLoadError';
      });
    } on Exception {
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _checkingAccess = false;
        _loading = false;
        _errorKey = 'usersLoadError';
      });
    }
  }

  void _updateFilters({String? blocked, String? disabled}) {
    setState(() {
      if (blocked != null) _blockedFilter = blocked;
      if (disabled != null) _disabledFilter = disabled;
      _cursorHistory
        ..clear()
        ..add(null);
    });
    _load(cursor: null, verifyAccess: false);
  }

  void _scheduleSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _cursorHistory
          ..clear()
          ..add(null);
      });
      _load(cursor: null, verifyAccess: false);
    });
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

  List<AdminUser> _sortedUsers() {
    final users = [...?_page?.users];
    int compareNullable(String? first, String? second) =>
        (first ?? '').toLowerCase().compareTo((second ?? '').toLowerCase());
    users.sort((first, second) {
      final comparison = switch (_sortColumn) {
        'name' => compareNullable(first.displayName ?? first.email,
            second.displayName ?? second.email),
        'email' => compareNullable(first.email, second.email),
        'lastSignIn' =>
          (first.lastSignIn ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(
                  second.lastSignIn ?? DateTime.fromMillisecondsSinceEpoch(0)),
        'state' => '${first.blocked}${first.disabled}'
            .compareTo('${second.blocked}${second.disabled}'),
        'plan' => first.plan.compareTo(second.plan),
        _ => first.createdAt.compareTo(second.createdAt),
      };
      return _sortAscending ? comparison : -comparison;
    });
    return users;
  }

  void _sortBy(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  Future<bool> _confirm(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(_t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(_t('confirm')),
              ),
            ],
          ),
        ) ??
        false;
  }

  String _userLabel(AdminUser user) {
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    return user.email ?? user.uid;
  }

  Future<void> _runAction(
    AdminUser user,
    _UserAction action,
  ) async {
    final name = _userLabel(user);
    final confirmation = switch (action) {
      _UserAction.block => ('confirmActionTitle', 'confirmBlockUser'),
      _UserAction.unblock => ('confirmActionTitle', 'confirmUnblockUser'),
      _UserAction.disable => ('confirmActionTitle', 'confirmDisableUser'),
      _UserAction.enable => ('confirmActionTitle', 'confirmEnableUser'),
      _UserAction.passwordReset => (
          'confirmActionTitle',
          'confirmPasswordReset',
        ),
      _UserAction.deletionRequest => (
          'confirmActionTitle',
          'confirmDeletionRequest',
        ),
    };
    if (!await _confirm(
      _t(confirmation.$1),
      _t(confirmation.$2, arguments: {'name': name}),
    )) {
      return;
    }

    setState(() => _busyUserUid = user.uid);
    try {
      switch (action) {
        case _UserAction.block:
          await widget.api.setUserBlocked(user.uid, true);
          break;
        case _UserAction.unblock:
          await widget.api.setUserBlocked(user.uid, false);
          break;
        case _UserAction.disable:
          await widget.api.setUserDisabled(user.uid, true);
          break;
        case _UserAction.enable:
          await widget.api.setUserDisabled(user.uid, false);
          break;
        case _UserAction.passwordReset:
          final email = user.email;
          if (email == null || email.isEmpty) {
            _showNotice(_t('noEmailForReset'));
            return;
          }
          await widget.api.requestPasswordReset(user.uid);
          final sender = widget.passwordResetSender;
          if (sender != null) {
            await sender(email);
          } else {
            await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
          }
          _showNotice(_t('passwordResetSent'));
          return;
        case _UserAction.deletionRequest:
          await widget.api.requestUserDataDeletion(user.uid);
          _showNotice(_t('dataDeletionRequested'));
          return;
      }
      _showNotice(_t('accountActionDone'));
      await _load(verifyAccess: false);
    } on Exception {
      if (mounted) _showNotice(_t('userActionFailed'));
    } finally {
      if (mounted) setState(() => _busyUserUid = null);
    }
  }

  Future<void> _showUsage(AdminUser user) async {
    setState(() => _busyUserUid = user.uid);
    try {
      final usage = await widget.api.loadUserUsage(user.uid);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_t('userUsage')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_t('usageForDate', arguments: {
                'date': MaterialLocalizations.of(context)
                    .formatMediumDate(usage.date.toLocal()),
              })),
              const SizedBox(height: AppSpacing.x3),
              Text(
                '${_t('dailySkinchatUsage')}: '
                '${usage.dailySkinchatUsage}',
              ),
              const SizedBox(height: AppSpacing.x2),
              Text('${_t('totalScans')}: ${usage.scansTotal}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_t('close')),
            ),
          ],
        ),
      );
    } on Exception {
      if (mounted) _showNotice(_t('userActionFailed'));
    } finally {
      if (mounted) setState(() => _busyUserUid = null);
    }
  }

  void _showNotice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _date(DateTime? value) {
    if (value == null) return _t('notAvailable');
    return MaterialLocalizations.of(context).formatMediumDate(value.toLocal());
  }

  PopupMenuButton<_UserAction> _actions(AdminUser user) {
    final actions = <(_UserAction, String)>[
      (_UserAction.block, 'blockUser'),
      (_UserAction.unblock, 'unblockUser'),
      (_UserAction.disable, 'disableUser'),
      (_UserAction.enable, 'enableUser'),
      (_UserAction.passwordReset, 'sendPasswordReset'),
      (_UserAction.deletionRequest, 'requestDataDeletion'),
    ];
    return PopupMenuButton<_UserAction>(
      tooltip: _t('userActions'),
      enabled: _busyUserUid == null,
      onSelected: (action) => _runAction(user, action),
      itemBuilder: (context) => [
        if (_busyUserUid == user.uid)
          PopupMenuItem(
            enabled: false,
            child: Text(_t('loading')),
          )
        else ...[
          for (final (action, label) in actions)
            if (_isActionVisible(user, action))
              PopupMenuItem(
                value: action,
                child: Text(_t(label)),
              ),
          PopupMenuItem(
            value: null,
            onTap: () => _showUsage(user),
            child: Text(_t('userUsage')),
          ),
        ],
      ],
      icon: const Icon(Icons.more_vert),
    );
  }

  bool _isActionVisible(AdminUser user, _UserAction action) => switch (action) {
        _UserAction.block => !user.blocked,
        _UserAction.unblock => user.blocked,
        _UserAction.disable => !user.disabled,
        _UserAction.enable => user.disabled,
        _UserAction.passwordReset || _UserAction.deletionRequest => true,
      };

  Widget _filters(double width) {
    final fieldWidth = width >= 720 ? 220.0 : (width < 180 ? 180.0 : width);
    return Wrap(
      spacing: AppSpacing.x3,
      runSpacing: AppSpacing.x3,
      children: [
        SizedBox(
          width: fieldWidth,
          child: TextField(
            controller: _searchController,
            onChanged: _scheduleSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: _t('usersSearch'),
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: fieldWidth,
          child: DropdownButtonFormField<String>(
            initialValue: _blockedFilter,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: _t('blockedFilter'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              _filterItem('all', 'allUsers'),
              _filterItem('blocked', 'blockedOnly'),
              _filterItem('unblocked', 'unblockedOnly'),
            ],
            onChanged: (value) {
              if (value != null) _updateFilters(blocked: value);
            },
          ),
        ),
        SizedBox(
          width: fieldWidth,
          child: DropdownButtonFormField<String>(
            initialValue: _disabledFilter,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: _t('disabledFilter'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              _filterItem('all', 'allUsers'),
              _filterItem('disabled', 'disabledOnly'),
              _filterItem('enabled', 'enabledOnly'),
            ],
            onChanged: (value) {
              if (value != null) _updateFilters(disabled: value);
            },
          ),
        ),
      ],
    );
  }

  DropdownMenuItem<String> _filterItem(String value, String label) =>
      DropdownMenuItem(value: value, child: Text(_t(label)));

  Widget _userCard(AdminUser user) {
    final theme = Theme.of(context);
    final status = [
      if (user.blocked) _t('blocked'),
      if (user.disabled) _t('disabled'),
      if (!user.blocked && !user.disabled) _t('active'),
    ].join(' · ');
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
                    _userLabel(user),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                _actions(user),
              ],
            ),
            if (user.email != null)
              SelectableText(
                user.email!,
                maxLines: 1,
              ),
            const SizedBox(height: AppSpacing.x2),
            Text('${_t('columnCreated')}: ${_date(user.createdAt)}'),
            Text('${_t('columnLastSignIn')}: ${_date(user.lastSignIn)}'),
            Text(
              '${_t('columnVerified')}: '
              '${_t(user.emailVerified ? 'yes' : 'no')}',
            ),
            Text('${_t('columnState')}: $status'),
            Text('${_t('columnPlan')}: ${_t('plan_${user.plan}')}'),
          ],
        ),
      ),
    );
  }

  DataColumn _column(String label, String key) => DataColumn(
        label: Text(label),
        onSort: (_, __) => _sortBy(key),
      );

  Widget _userTable(List<AdminUser> users) {
    final sortColumnIndex = switch (_sortColumn) {
      'name' => 0,
      'email' => 1,
      'created' => 2,
      'lastSignIn' => 3,
      'state' => 5,
      'plan' => 6,
      _ => 2,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        sortColumnIndex: sortColumnIndex,
        sortAscending: _sortAscending,
        columns: [
          _column(_t('columnName'), 'name'),
          _column(_t('columnEmail'), 'email'),
          _column(_t('columnCreated'), 'created'),
          _column(_t('columnLastSignIn'), 'lastSignIn'),
          DataColumn(label: Text(_t('columnVerified'))),
          _column(_t('columnState'), 'state'),
          _column(_t('columnPlan'), 'plan'),
          DataColumn(label: Text(_t('userActions'))),
        ],
        rows: [
          for (final user in users)
            DataRow(
              cells: [
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      _userLabel(user),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(Text(user.email ?? _t('notAvailable'))),
                DataCell(Text(_date(user.createdAt))),
                DataCell(Text(_date(user.lastSignIn))),
                DataCell(Text(_t(user.emailVerified ? 'yes' : 'no'))),
                DataCell(
                  Text(
                    user.blocked
                        ? _t('blocked')
                        : user.disabled
                            ? _t('disabled')
                            : _t('active'),
                  ),
                ),
                DataCell(Text(_t('plan_${user.plan}'))),
                DataCell(_actions(user)),
              ],
            ),
        ],
      ),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _errorKey == 'adminDenied'
                    ? Icons.lock_outline_rounded
                    : Icons.cloud_off_outlined,
                size: 40,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(height: AppSpacing.x3),
              Text(_t(_errorKey!), textAlign: TextAlign.center),
              if (_errorKey != 'adminDenied') ...[
                const SizedBox(height: AppSpacing.x3),
                FilledButton.tonal(
                  onPressed: _load,
                  child: Text(_t('retry')),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final page = _page;
    if (!_isAdmin || page == null) {
      return Center(child: Text(_t('adminDenied')));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          constraints.maxWidth,
          AppBreakpoints.contentMaxWidth,
        );
        final users = _sortedUsers();
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
                              _t('usersSubtitle'),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: AppSpacing.x3),
                            _filters(width - AppSpacing.x8),
                            const SizedBox(height: AppSpacing.x2),
                            Text(
                              _t('usersPrivacyNote'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (_loading) const LinearProgressIndicator(),
                Expanded(
                  child: users.isEmpty && !_loading
                      ? Center(child: Text(_t('noUsers')))
                      : width >= 800
                          ? SingleChildScrollView(
                              child: _userTable(users),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.x3,
                              ),
                              itemCount: users.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: AppSpacing.x2),
                              itemBuilder: (context, index) =>
                                  _userCard(users[index]),
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('usersTitle')),
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
}

enum _UserAction {
  block,
  unblock,
  disable,
  enable,
  passwordReset,
  deletionRequest,
}
