import 'package:flutter/material.dart';
import 'dart:async';

import '../localization/app_localizations.dart';
import '../local_reminder_service.dart';
import '../routines/routine_controller.dart';
import '../routines/routine_models.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({
    super.key,
    required this.controller,
    required this.language,
    required this.onOpenDeepLink,
    required this.onMasterChanged,
    this.onSettingsChanged,
  });

  final RoutineController controller;
  final String language;
  final ValueChanged<Uri> onOpenDeepLink;
  final Future<void> Function(bool enabled) onMasterChanged;
  final Future<void> Function(RoutineNotificationSettings settings)?
      onSettingsChanged;

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  String _filter = 'all';
  String _categoryFilter = 'all';
  final _searchController = TextEditingController();
  AppLocalizations? _localizations;

  String _t(String key, {Map<String, String> arguments = const {}}) =>
      _localizations!.text(
        key,
        domain: 'notifications',
        arguments: arguments,
      );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _localizations = Localizations.of<AppLocalizations>(
          context,
          AppLocalizations,
        ) ??
        AppLocalizations.forLanguageCode(widget.language);
    final theme = Theme.of(context);
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final search = _searchController.text.trim().toLowerCase();
        final items = controller.notifications.where((item) {
          if (_filter == 'unread' && item.read) return false;
          if (_filter == 'read' && !item.read) return false;
          if (_filter == 'important' && !item.important) return false;
          if (_categoryFilter != 'all' &&
              _categoryFilter != _normalizedCategory(item.category)) {
            return false;
          }
          if (search.isNotEmpty &&
              !_localized(item, item.title, item.titleKey)
                  .toLowerCase()
                  .contains(search) &&
              !_localized(item, item.body, item.bodyKey)
                  .toLowerCase()
                  .contains(search)) {
            return false;
          }
          return true;
        }).toList()
          ..sort(
              (first, second) => second.createdAt.compareTo(first.createdAt));
        final groups = <String, List<RoutineNotification>>{};
        for (final item in items) {
          groups.putIfAbsent(_dateGroup(context, item.createdAt), () => []);
          groups[_dateGroup(context, item.createdAt)]!.add(item);
        }
        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: theme.scaffoldBackgroundColor,
            foregroundColor: theme.colorScheme.onSurface,
            elevation: 0,
            automaticallyImplyLeading: false,
            leading: IconButton(
              tooltip: _t('back'),
              onPressed: () => Navigator.of(context).pop(),
              icon: const BackButtonIcon(),
            ),
            title: Text(
              _t('notifications'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            actions: [
              IconButton(
                tooltip: _t('notificationSettings'),
                onPressed: _openSettings,
                icon: const Icon(Icons.tune_rounded),
              ),
              PopupMenuButton<String>(
                tooltip: _t('more'),
                onSelected: (value) {
                  if (value == 'read') {
                    controller.markAllRead();
                  } else if (value == 'clear') {
                    _confirmClear();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'read',
                    child: Text(_t('markAllRead')),
                  ),
                  PopupMenuItem(
                    value: 'clear',
                    child: Text(_t('clearAll')),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (final filter in [
                      'all',
                      'unread',
                      'read',
                      'important',
                    ])
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          label: Text(_t(filter)),
                          selected: _filter == filter,
                          onSelected: (_) => setState(() => _filter = filter),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: _t('searchNotifications'),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: _t('clearSearch'),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
                child: DropdownButtonFormField<String>(
                  initialValue: _categoryFilter,
                  decoration: InputDecoration(
                    labelText: _t('category'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    isDense: true,
                  ),
                  items: [
                    for (final category in const [
                      'all',
                      'reminder',
                      'routine',
                      'scan',
                      'update',
                      'message',
                      'appointment',
                      'subscription',
                      'security',
                      'other',
                    ])
                      DropdownMenuItem(
                        value: category,
                        child: Text(
                          category == 'all'
                              ? _t('allCategories')
                              : category == 'other'
                                  ? _t('otherCategory')
                                  : _t(category),
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(
                    () => _categoryFilter = value ?? 'all',
                  ),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? _emptyState(
                        search.isNotEmpty
                            ? 'noSearchResults'
                            : _filter != 'all' || _categoryFilter != 'all'
                                ? 'noFilteredNotifications'
                                : 'emptyNotifications',
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                        children: [
                          for (final entry in groups.entries) ...[
                            Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                4,
                                10,
                                4,
                                4,
                              ),
                              child: Text(
                                entry.key,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            for (final item in entry.value)
                              _notificationCard(context, item),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _localized(
    RoutineNotification item,
    String fallback,
    String? key,
  ) {
    if (key == null) return fallback;
    return _t(key, arguments: item.parameters);
  }

  String _normalizedCategory(String category) => switch (category) {
        'doctor_reply' => 'message',
        'appointment_reminder' => 'appointment',
        'subscription_expiration' => 'subscription',
        'security_alert' => 'security',
        'system_update' => 'update',
        'daily_reminder' => 'reminder',
        'sunscreen_reminder' || 'hydration_reminder' => 'reminder',
        'scan_result_available' || 'scan_checkin' => 'scan',
        'reminder' ||
        'routine' ||
        'scan' ||
        'update' ||
        'message' ||
        'appointment' ||
        'subscription' ||
        'security' ||
        'other' =>
          category,
        _ => 'other',
      };

  String _dateGroup(BuildContext context, DateTime createdAt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final localCreatedAt = createdAt.toLocal();
    final day = DateTime(
      localCreatedAt.year,
      localCreatedAt.month,
      localCreatedAt.day,
    );
    if (day == today) return _t('today');
    if (day == today.subtract(const Duration(days: 1))) {
      return _t('yesterday');
    }
    return MaterialLocalizations.of(context).formatMediumDate(localCreatedAt);
  }

  Widget _notificationCard(
    BuildContext context,
    RoutineNotification item,
  ) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.error,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          color: theme.colorScheme.onError,
        ),
      ),
      onDismissed: (_) async {
        final removed = await controller.deleteNotification(item.id);
        if (removed == null || !context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(_t('notificationDeleted')),
              action: SnackBarAction(
                label: _t('undo'),
                onPressed: () => unawaited(
                  controller.restoreNotifications([removed]),
                ),
              ),
            ),
          );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 5),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: item.important
                ? theme.colorScheme.error.withValues(alpha: 0.6)
                : item.read
                    ? theme.colorScheme.outlineVariant
                    : theme.colorScheme.primary.withValues(alpha: 0.65),
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsetsDirectional.fromSTEB(14, 8, 6, 8),
          onTap: () async {
            await controller.markRead(item.id);
            final link = item.deepLink;
            if (link != null) {
              final uri = Uri.tryParse(link);
              if (uri != null) widget.onOpenDeepLink(uri);
            }
          },
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              _notificationIcon(item),
              if (!item.read)
                PositionedDirectional(
                  top: -2,
                  end: -2,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          title: Text(
            _localized(item, item.title, item.titleKey),
            style: TextStyle(
              fontWeight: item.read ? FontWeight.w500 : FontWeight.w800,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_localized(item, item.body, item.bodyKey)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _t(_normalizedCategory(item.category) == 'other'
                          ? 'otherCategory'
                          : _normalizedCategory(item.category)),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text('•', style: theme.textTheme.labelSmall),
                    Text(
                      _relativeTime(item.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (item.important)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(_t('important')),
                        avatar: Icon(
                          Icons.priority_high_rounded,
                          size: 15,
                          color: theme.colorScheme.error,
                        ),
                        labelStyle: theme.textTheme.labelSmall,
                        side: BorderSide(
                          color: theme.colorScheme.error.withValues(alpha: 0.5),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ],
            ),
          ),
          trailing: PopupMenuButton<String>(
            tooltip: _t('more'),
            onSelected: (action) async {
              if (action == 'read') await controller.markRead(item.id);
              if (action == 'delete') {
                final removed = await controller.deleteNotification(item.id);
                if (!context.mounted || removed == null) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(_t('notificationDeleted')),
                      action: SnackBarAction(
                        label: _t('undo'),
                        onPressed: () => unawaited(
                          controller.restoreNotifications([removed]),
                        ),
                      ),
                    ),
                  );
              }
            },
            itemBuilder: (context) => [
              if (!item.read)
                PopupMenuItem(
                  value: 'read',
                  child: Text(_t('markAsRead')),
                ),
              PopupMenuItem(
                value: 'delete',
                child: Text(_t('deleteNotification')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _notificationIcon(RoutineNotification item) {
    final theme = Theme.of(context);
    final (icon, color) = switch (item.category) {
      'reminder' => (Icons.alarm_rounded, const Color(0xFF168CFF)),
      'routine' => (Icons.check_circle_outline_rounded, Colors.green),
      'scan' => (Icons.center_focus_strong_rounded, const Color(0xFF8667FF)),
      'update' => (Icons.campaign_outlined, Colors.orange),
      'message' => (Icons.chat_bubble_outline_rounded, Colors.teal),
      'appointment' || 'appointment_reminder' => (
          Icons.event_outlined,
          Colors.indigo
        ),
      'subscription' || 'subscription_expiration' => (
          Icons.workspace_premium_outlined,
          Colors.amber
        ),
      'security' || 'security_alert' => (
          Icons.security_rounded,
          theme.colorScheme.error
        ),
      _ => (Icons.notifications_none_rounded, theme.colorScheme.primary),
    };
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.13),
      child: Icon(icon, color: color),
    );
  }

  Widget _emptyState(String messageKey) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_off_outlined,
              size: 52,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              _t(messageKey),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationSettingsScreen(
          controller: widget.controller,
          language: widget.language,
          onMasterChanged: widget.onMasterChanged,
          onSettingsChanged: widget.onSettingsChanged,
        ),
      ),
    );
  }

  Future<void> _confirmClear() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('clearAll')),
        content: Text(_t('clearConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('clear')),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final removed = await widget.controller.clearNotifications();
      if (removed.isEmpty || !mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_t('notificationsCleared')),
            action: SnackBarAction(
              label: _t('undo'),
              onPressed: () => unawaited(
                widget.controller.restoreNotifications(removed),
              ),
            ),
          ),
        );
    }
  }

  String _relativeTime(DateTime createdAt) {
    final difference = DateTime.now().difference(createdAt);
    if (difference.isNegative) {
      final remaining = difference.abs();
      if (remaining.inMinutes < 1) return _t('justNow');
      if (remaining.inHours < 1) {
        return _t('minutesUntil', arguments: {
          'count': remaining.inMinutes.toString(),
        });
      }
      if (remaining.inDays < 1) {
        return _t('hoursUntil', arguments: {
          'count': remaining.inHours.toString(),
        });
      }
      return _t('daysUntil', arguments: {
        'count': remaining.inDays.toString(),
      });
    }
    if (difference.inMinutes < 1) return _t('justNow');
    if (difference.inHours < 1) {
      return _t('minutesAgo', arguments: {
        'count': difference.inMinutes.toString(),
      });
    }
    if (difference.inDays < 1) {
      return _t('hoursAgo', arguments: {
        'count': difference.inHours.toString(),
      });
    }
    return _t('daysAgo', arguments: {
      'count': difference.inDays.toString(),
    });
  }
}

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({
    super.key,
    required this.controller,
    required this.language,
    required this.onMasterChanged,
    this.onSettingsChanged,
  });

  final RoutineController controller;
  final String language;
  final Future<void> Function(bool enabled) onMasterChanged;
  final Future<void> Function(RoutineNotificationSettings settings)?
      onSettingsChanged;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  AppLocalizations? _localizations;
  bool? _permissionGranted;

  String _t(String key) => _localizations!.text(key, domain: 'notifications');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPermission());
    }
  }

  @override
  Widget build(BuildContext context) {
    _localizations = Localizations.of<AppLocalizations>(
          context,
          AppLocalizations,
        ) ??
        AppLocalizations.forLanguageCode(widget.language);
    final controller = widget.controller;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(_t('notificationSettings'))),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final settings = controller.notificationSettings;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
            children: [
              Card(
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      title: Text(_t('masterNotifications')),
                      subtitle: Text(_t('permissionExplanation')),
                      value: settings.masterEnabled &&
                          controller.supportsNotifications &&
                          (_permissionGranted ?? true),
                      onChanged:
                          controller.supportsNotifications ? _setMaster : null,
                    ),
                    if (_permissionGranted != null)
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          16,
                          0,
                          16,
                          12,
                        ),
                        child: Text(
                          _t(!controller.supportsNotifications
                              ? 'permissionUnsupported'
                              : _permissionGranted!
                                  ? 'permissionStatusGranted'
                                  : 'permissionStatusDenied'),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: _permissionGranted == true &&
                                            controller.supportsNotifications
                                        ? scheme.primary
                                        : scheme.error,
                                  ),
                        ),
                      ),
                    const Divider(height: 1),
                    _sectionTitle(_t('routineNotifications')),
                    _switch(
                        'dailyEnabled',
                        settings.dailyEnabled,
                        (value) =>
                            _update(settings.copyWith(dailyEnabled: value))),
                    _switch(
                        'morningEnabled',
                        settings.morningEnabled,
                        (value) =>
                            _update(settings.copyWith(morningEnabled: value))),
                    _switch(
                        'eveningEnabled',
                        settings.eveningEnabled,
                        (value) =>
                            _update(settings.copyWith(eveningEnabled: value))),
                    _switch(
                        'sunscreenEnabled',
                        settings.sunscreenEnabled,
                        (value) => _update(
                            settings.copyWith(sunscreenEnabled: value))),
                    _switch(
                        'hydrationEnabled',
                        settings.hydrationEnabled,
                        (value) => _update(
                            settings.copyWith(hydrationEnabled: value))),
                    _switch(
                        'aiScanEnabled',
                        settings.aiScanEnabled,
                        (value) =>
                            _update(settings.copyWith(aiScanEnabled: value))),
                    _switch(
                        'weeklySummaryEnabled',
                        settings.weeklySummaryEnabled,
                        (value) => _update(
                            settings.copyWith(weeklySummaryEnabled: value))),
                    const Divider(height: 1),
                    _sectionTitle(_t('activityNotifications')),
                    _switch(
                      'doctorMessagesEnabled',
                      settings.doctorMessagesEnabled,
                      (value) => _update(
                        settings.copyWith(doctorMessagesEnabled: value),
                      ),
                    ),
                    _switch(
                      'appointmentRemindersEnabled',
                      settings.appointmentRemindersEnabled,
                      (value) => _update(
                        settings.copyWith(appointmentRemindersEnabled: value),
                      ),
                    ),
                    _switch(
                      'subscriptionAlertsEnabled',
                      settings.subscriptionAlertsEnabled,
                      (value) => _update(
                        settings.copyWith(subscriptionAlertsEnabled: value),
                      ),
                    ),
                    _switch(
                      'systemUpdatesEnabled',
                      settings.systemUpdatesEnabled,
                      (value) => _update(
                        settings.copyWith(systemUpdatesEnabled: value),
                      ),
                    ),
                    _switch(
                      'securityAlertsEnabled',
                      settings.securityAlertsEnabled,
                      (value) => _update(
                        settings.copyWith(securityAlertsEnabled: value),
                      ),
                    ),
                  ],
                ),
              ),
              Card(
                child: Column(
                  children: [
                    _sectionTitle(_t('deliveryPreferences')),
                    _switch(
                        'soundEnabled',
                        settings.soundEnabled,
                        (value) =>
                            _update(settings.copyWith(soundEnabled: value))),
                    _switch(
                        'vibrationEnabled',
                        settings.vibrationEnabled,
                        (value) => _update(
                            settings.copyWith(vibrationEnabled: value))),
                    _switch(
                        'privatePreview',
                        settings.privatePreview,
                        (value) =>
                            _update(settings.copyWith(privatePreview: value))),
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        16,
                        0,
                        16,
                        12,
                      ),
                      child: Text(
                        _t('privatePreviewDescription'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                    _switch(
                        'quietHoursEnabled',
                        settings.quietHoursEnabled,
                        (value) => _update(
                            settings.copyWith(quietHoursEnabled: value))),
                    if (settings.quietHoursEnabled) ...[
                      _timeRow(
                        _t('quietStart'),
                        settings.quietStartMinutes,
                        (value) => _update(
                          settings.copyWith(quietStartMinutes: value),
                        ),
                      ),
                      _timeRow(
                        _t('quietEnd'),
                        settings.quietEndMinutes,
                        (value) =>
                            _update(settings.copyWith(quietEndMinutes: value)),
                      ),
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          16,
                          0,
                          16,
                          12,
                        ),
                        child: Text(
                          _t('quietHoursDescription'),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: OutlinedButton.icon(
                  onPressed: _preview,
                  icon: const Icon(Icons.volume_up_outlined),
                  label: Text(_t('previewAlert')),
                ),
              ),
              Text(
                _t('platformAlertNote'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String title) => ListTile(
        dense: true,
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );

  Widget _switch(
    String key,
    bool value,
    ValueChanged<bool> onChanged,
  ) =>
      SwitchListTile.adaptive(
        title: Text(_t(key)),
        value: value,
        onChanged: onChanged,
      );

  Widget _timeRow(
    String title,
    int minutes,
    ValueChanged<int> onChanged,
  ) =>
      ListTile(
        title: Text(title),
        trailing: Text(
          TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context),
        ),
        onTap: () async {
          final time = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
          );
          if (time != null) onChanged(time.hour * 60 + time.minute);
        },
      );

  Future<void> _setMaster(bool enabled) async {
    if (enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_t('masterNotifications')),
          content: Text(_t('permissionExplanation')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_t('continue')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await widget.onMasterChanged(enabled);
      if (!mounted) return;
      final settings = widget.controller.notificationSettings;
      if (settings.masterEnabled != enabled) {
        await widget.controller.updateNotificationSettings(
          settings.copyWith(masterEnabled: enabled),
        );
      }
      await _refreshPermission();
    } on ReminderPermissionDeniedException {
      if (mounted) _showNotice(_t('permissionDenied'));
    } on RoutineNotificationPermissionDenied {
      if (mounted) _showNotice(_t('permissionDenied'));
    } on Exception catch (error) {
      if (mounted) _showNotice('${_t('settingsError')}: $error');
    }
  }

  Future<void> _refreshPermission() async {
    late final bool granted;
    try {
      granted = await widget.controller.notificationPermissionGranted;
    } on Exception catch (error) {
      if (mounted) _showNotice('${_t('settingsError')}: $error');
      return;
    }
    if (!mounted) return;
    if (_permissionGranted != granted) {
      setState(() => _permissionGranted = granted);
    }
    if (!granted && widget.controller.notificationSettings.masterEnabled) {
      try {
        await widget.onMasterChanged(false);
      } on Exception catch (error) {
        if (mounted) _showNotice('${_t('settingsError')}: $error');
      }
    }
  }

  Future<void> _update(RoutineNotificationSettings settings) async {
    try {
      final onSettingsChanged = widget.onSettingsChanged;
      if (onSettingsChanged == null) {
        await widget.controller.updateNotificationSettings(settings);
      } else {
        await onSettingsChanged(settings);
      }
    } on RoutineNotificationPermissionDenied {
      if (mounted) _showNotice(_t('permissionDenied'));
    } on Exception catch (error) {
      if (mounted) _showNotice('${_t('settingsError')}: $error');
    }
  }

  Future<void> _preview() async {
    try {
      await widget.controller.previewAlert(
        title: _t('previewTitle'),
        body: _t('previewBody'),
      );
    } on RoutineNotificationPermissionDenied {
      if (mounted) _showNotice(_t('permissionDenied'));
    } on Exception catch (error) {
      if (mounted) _showNotice('${_t('settingsError')}: $error');
    }
  }

  void _showNotice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
