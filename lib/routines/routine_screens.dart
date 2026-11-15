import 'dart:async';

import 'package:flutter/material.dart';

import '../design/app_design_system.dart';
import '../localization/app_localizations.dart';
import 'routine_controller.dart';
import 'routine_models.dart';

class RoutineDashboardScreen extends StatefulWidget {
  const RoutineDashboardScreen({
    super.key,
    required this.controller,
    required this.language,
    required this.accentColor,
    this.onOpenWidgets,
  });

  final RoutineController controller;
  final String language;
  final Color accentColor;
  final VoidCallback? onOpenWidgets;

  @override
  State<RoutineDashboardScreen> createState() => _RoutineDashboardScreenState();
}

class _RoutineDashboardScreenState extends State<RoutineDashboardScreen> {
  late DateTime _selectedDay = DateTime.now();

  Map<String, String> get _text =>
      AppLocalizations.forLanguageCode(widget.language).domain('routines');

  String _t(String key) {
    final localization = AppLocalizations.forLanguageCode(widget.language);
    if (localization.domain('routines').containsKey(key)) {
      return localization.text(key, domain: 'routines');
    }
    return localization.text(key, domain: 'widgets');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DefaultTabController(
      length: 2,
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _t('routines'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _t('addTask'),
                    onPressed: () => _editTask(),
                    icon: Icon(Icons.add_circle_outline,
                        color: widget.accentColor),
                  ),
                  if (widget.onOpenWidgets != null)
                    IconButton(
                      tooltip: _t('widgets'),
                      onPressed: widget.onOpenWidgets,
                      icon: Icon(Icons.widgets_outlined,
                          color: widget.accentColor),
                    ),
                ],
              ),
            ),
            TabBar(
              indicatorColor: widget.accentColor,
              labelColor: widget.accentColor,
              unselectedLabelColor: scheme.onSurfaceVariant,
              tabs: [
                Tab(text: _t('daily')),
                Tab(text: _t('weekly')),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _dailyView(),
                  _weeklyView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dailyView() {
    final today = DateTime.now();
    return _taskList(
      day: today,
      showProgress: true,
    );
  }

  Widget _weeklyView() {
    final controller = widget.controller;
    final weekStart = RoutineController.weekStart(_selectedDay);
    final weekTotal = controller.taskCountForWeek(weekStart);
    final weekDone = controller.completedCountForWeek(weekStart);
    final percent = weekTotal == 0 ? 0 : (weekDone / weekTotal * 100).round();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selectedTasks = controller.tasksForDay(_selectedDay);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _t('weeklyProgress'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '$percent%',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: widget.accentColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    begin: 0,
                    end: weekTotal == 0 ? 0 : weekDone / weekTotal,
                  ),
                  duration: const Duration(milliseconds: 350),
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(8),
                    color: widget.accentColor,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(7, (index) {
                    final date = weekStart.add(Duration(days: index));
                    final progress = controller.dailyProgress(date);
                    final selected = RoutineTask.dayKey(date) ==
                        RoutineTask.dayKey(_selectedDay);
                    return InkWell(
                      onTap: () => setState(() => _selectedDay = date),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 4,
                        ),
                        child: Column(
                          children: [
                            Text(
                              _t(_weekdayKeys[index]),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: selected
                                    ? widget.accentColor
                                    : scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected
                                    ? widget.accentColor
                                    : widget.accentColor.withValues(
                                        alpha: progress > 0 ? 0.18 : 0.07),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? widget.accentColor
                                      : scheme.outlineVariant,
                                ),
                              ),
                              child: Text(
                                '${date.day}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: selected
                                      ? scheme.onPrimary
                                      : scheme.onSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            SizedBox(
                              width: 28,
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 3,
                                borderRadius: BorderRadius.circular(3),
                                color: widget.accentColor,
                                backgroundColor: scheme.surfaceContainerHighest,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _statCard(
                _t('completedTasks'),
                '$weekDone / $weekTotal',
                Icons.task_alt_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                _t('currentStreak'),
                '${controller.currentStreak} ${_t('days')}',
                Icons.local_fire_department_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                _t('consistency'),
                '${controller.consistencyPercent(7)}%',
                Icons.auto_graph_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                '${_t('tasksFor')} ${_weekdayName(_selectedDay.weekday)} ${_selectedDay.day}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: _t('copyToDay'),
              onPressed: () => _copyRoutine(_selectedDay),
              icon: Icon(Icons.copy_all_rounded, color: widget.accentColor),
            ),
            IconButton(
              tooltip: _t('resetWeek'),
              onPressed: _confirmResetWeek,
              icon: Icon(Icons.restart_alt_rounded, color: scheme.error),
            ),
          ],
        ),
        if (selectedTasks.isEmpty)
          _emptyState()
        else
          _periodSections(_selectedDay),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.icon(
            onPressed: () => _editTask(day: _selectedDay),
            icon: const Icon(Icons.add_rounded),
            label: Text(_t('addTask')),
          ),
        ),
      ],
    );
  }

  Widget _statCard(String title, String value, IconData icon) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: widget.accentColor),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _taskList({
    required DateTime day,
    required bool showProgress,
  }) {
    final tasks = widget.controller.tasksForDay(day);
    final total = tasks.length;
    final completed = widget.controller.completedCount(day);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (showProgress) ...[
          _dailyProgressCard(completed: completed, total: total),
          const SizedBox(height: 8),
        ],
        if (tasks.isEmpty) _emptyState() else _periodSections(day),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.icon(
            onPressed: () => _editTask(day: day),
            icon: const Icon(Icons.add_rounded),
            label: Text(_t('addTask')),
          ),
        ),
      ],
    );
  }

  Widget _dailyProgressCard({required int completed, required int total}) {
    final theme = Theme.of(context);
    final progress = total == 0 ? 0.0 : completed / total;
    return Card(
      key: const ValueKey('routine-daily-progress'),
            child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Row(
                children: [
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                alignment: Alignment.center,
                    children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 350),
                    builder: (context, value, _) => CircularProgressIndicator(
                      value: value,
                      strokeWidth: 6,
                      color: widget.accentColor,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  Text(
                    '${(progress * 100).round()}%',
                    style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ],
                      ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                      Text(
                    _t('todaysProgress'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  const SizedBox(height: AppSpacing.x1),
                  Text(
                    '$completed / $total ${_t('completed')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                  ),
                    ),
                  const SizedBox(height: AppSpacing.x2),
                  Wrap(
                    spacing: AppSpacing.x3,
                    runSpacing: AppSpacing.x1,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${total - completed} ${_t('remaining')}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_fire_department_rounded,
                            color: widget.accentColor,
                            size: 16,
                          ),
                          const SizedBox(width: AppSpacing.x1),
                          Flexible(
                            child: Text(
                              '${widget.controller.currentStreak} ${_t('dayStreak')}',
                              softWrap: true,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                          ),
                        ],
                      ),
                ],
              ),
                ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _periodSections(DateTime day) {
    final sections = [
      for (final period in RoutinePeriod.values) _periodSection(day, period),
    ];
    if (AppBreakpoints.of(context) != AppViewport.expanded) {
      return Column(children: sections);
    }

    final middle = (sections.length / 2).ceil();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: sections.take(middle).toList(),
          ),
        ),
        const SizedBox(width: AppSpacing.x4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: sections.skip(middle).toList(),
          ),
        ),
      ],
    );
  }

  Widget _periodSection(DateTime day, RoutinePeriod period) {
    final tasks = widget.controller.tasksForDay(day, period: period)
      ..sort((first, second) =>
          first.reminderMinutes.compareTo(second.reminderMinutes));
    if (tasks.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 4, 4),
            child: Text(
              _t(period.name),
              style: theme.textTheme.labelLarge?.copyWith(
                color: widget.accentColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (final task in tasks)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                onTap: () => _toggleTask(task, day),
                leading: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    task.isCompletedOn(day)
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    key: ValueKey(task.isCompletedOn(day)),
                    color: task.isCompletedOn(day)
                        ? widget.accentColor
                        : theme.colorScheme.outline,
                  ),
                ),
                title: Text(
                  task.title,
                  style: TextStyle(
                    decoration: task.isCompletedOn(day)
                        ? TextDecoration.lineThrough
                        : null,
                    color: task.isCompletedOn(day)
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  '${TimeOfDay(
                    hour: task.reminderMinutes ~/ 60,
                    minute: task.reminderMinutes % 60,
                  ).format(context)}'
                  '${task.reminderEnabled ? ' • ${_t('reminderOn')}' : ''}',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      _editTask(task: task, day: day);
                    } else if (value == 'delete') {
                      unawaited(widget.controller.deleteTask(task.id));
                    } else if (value == 'reminder') {
                      unawaited(_toggleReminder(task));
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'edit', child: Text(_t('edit'))),
                    PopupMenuItem(
                      value: 'reminder',
                      child: Text(
                        task.reminderEnabled
                            ? _t('disableReminder')
                            : _t('enableReminder'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(_t('delete')),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Icon(
            Icons.spa_outlined,
            size: 44,
            color: widget.accentColor.withValues(alpha: 0.8),
          ),
          const SizedBox(height: 12),
          Text(
            _t('emptyRoutine'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleTask(RoutineTask task, DateTime day) async {
    try {
      await widget.controller.toggleCompletion(task.id, day);
    } on Exception catch (error) {
      if (mounted) _showNotice('${_t('saveFailed')}: $error');
    }
  }

  Future<void> _toggleReminder(RoutineTask task) async {
    try {
      await widget.controller.updateTask(
        task.copyWith(reminderEnabled: !task.reminderEnabled),
      );
    } on RoutineNotificationPermissionDenied {
      if (mounted) _showNotice(_t('permissionDenied'));
    } on Exception catch (error) {
      if (mounted) _showNotice('${_t('scheduleFailed')}: $error');
    }
  }

  Future<void> _editTask({RoutineTask? task, DateTime? day}) async {
    final result = await showModalBottomSheet<RoutineTaskDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => RoutineTaskEditor(
        initialTask: task,
        initialDay: day ?? DateTime.now(),
        labels: _text,
        accentColor: widget.accentColor,
      ),
    );
    if (result == null) return;
    try {
      if (task == null) {
        await widget.controller.addTask(
          title: result.title,
          period: result.period,
          weekdays: result.weekdays,
          reminderMinutes: result.reminderMinutes,
          reminderEnabled: result.reminderEnabled,
        );
      } else {
        await widget.controller.updateTask(
          task.copyWith(
            title: result.title,
            period: result.period,
            weekdays: result.weekdays,
            reminderMinutes: result.reminderMinutes,
            reminderEnabled: result.reminderEnabled,
          ),
        );
      }
    } on RoutineNotificationPermissionDenied {
      if (mounted) _showNotice(_t('permissionDenied'));
    } on Exception catch (error) {
      if (mounted) _showNotice('${_t('scheduleFailed')}: $error');
    }
  }

  Future<void> _copyRoutine(DateTime source) async {
    final targetDate = await showDatePicker(
      context: context,
      initialDate: source.add(const Duration(days: 1)),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: _t('copyToDay'),
    );
    if (targetDate == null) return;
    try {
      await widget.controller.copyDayRoutine(source, targetDate);
    } on Exception catch (error) {
      if (mounted) _showNotice('${_t('saveFailed')}: $error');
    }
  }

  Future<void> _confirmResetWeek() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('resetWeek')),
        content: Text(_t('resetWeekConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('reset')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await widget.controller.resetWeek(weekOf: _selectedDay);
      } on Exception catch (error) {
        if (mounted) _showNotice('${_t('saveFailed')}: $error');
      }
    }
  }

  String _weekdayName(int weekday) => _t(_weekdayKeys[weekday - 1]);

  void _showNotice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class RoutineTaskDraft {
  const RoutineTaskDraft({
    required this.title,
    required this.period,
    required this.weekdays,
    required this.reminderMinutes,
    required this.reminderEnabled,
  });

  final String title;
  final RoutinePeriod period;
  final List<int> weekdays;
  final int reminderMinutes;
  final bool reminderEnabled;
}

class RoutineTaskEditor extends StatefulWidget {
  const RoutineTaskEditor({
    super.key,
    required this.initialTask,
    required this.initialDay,
    required this.labels,
    required this.accentColor,
  });

  final RoutineTask? initialTask;
  final DateTime initialDay;
  final Map<String, String> labels;
  final Color accentColor;

  @override
  State<RoutineTaskEditor> createState() => _RoutineTaskEditorState();
}

class _RoutineTaskEditorState extends State<RoutineTaskEditor> {
  late final TextEditingController _titleController = TextEditingController(
    text: widget.initialTask?.title ?? '',
  );
  late RoutinePeriod _period =
      widget.initialTask?.period ?? RoutinePeriod.morning;
  late final Set<int> _weekdays = {
    ...(widget.initialTask?.weekdays ?? [widget.initialDay.weekday]),
  };
  late int _reminderMinutes = widget.initialTask?.reminderMinutes ?? 8 * 60;
  late bool _reminderEnabled = widget.initialTask?.reminderEnabled ?? false;

  String _t(String key) => widget.labels[key]!;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.initialTask == null ? _t('addTask') : _t('editTask'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                autofocus: widget.initialTask == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: _t('taskName'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<RoutinePeriod>(
                initialValue: _period,
                decoration: InputDecoration(
                  labelText: _t('period'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final period in RoutinePeriod.values)
                    DropdownMenuItem(
                      value: period,
                      child: Text(_t(period.name)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _period = value);
                },
              ),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  _t('repeatDays'),
                  style: theme.textTheme.labelLarge,
                ),
              ),
              Wrap(
                spacing: 4,
                children: List.generate(7, (index) {
                  final day = index + 1;
                  return FilterChip(
                    label: Text(_t(_weekdayKeys[index])),
                    selected: _weekdays.contains(day),
                    selectedColor: widget.accentColor.withValues(alpha: 0.18),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _weekdays.add(day);
                      } else {
                        _weekdays.remove(day);
                      }
                    }),
                  );
                }),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading:
                    Icon(Icons.schedule_rounded, color: widget.accentColor),
                title: Text(_t('reminderTime')),
                trailing: Text(
                  TimeOfDay(
                    hour: _reminderMinutes ~/ 60,
                    minute: _reminderMinutes % 60,
                  ).format(context),
                ),
                onTap: () async {
                  final selected = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(
                      hour: _reminderMinutes ~/ 60,
                      minute: _reminderMinutes % 60,
                    ),
                  );
                  if (selected != null) {
                    setState(() => _reminderMinutes =
                        selected.hour * 60 + selected.minute);
                  }
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(_t('reminderEnabled')),
                value: _reminderEnabled,
                onChanged: (value) => setState(() => _reminderEnabled = value),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _save,
                child: Text(_t('save')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty || _weekdays.isEmpty) return;
    Navigator.pop(
      context,
      RoutineTaskDraft(
        title: title,
        period: _period,
        weekdays: _weekdays.toList()..sort(),
        reminderMinutes: _reminderMinutes,
        reminderEnabled: _reminderEnabled,
      ),
    );
  }
}

class WidgetGalleryScreen extends StatefulWidget {
  const WidgetGalleryScreen({
    super.key,
    required this.controller,
    required this.language,
  });

  final RoutineController controller;
  final String language;

  @override
  State<WidgetGalleryScreen> createState() => _WidgetGalleryScreenState();
}

class _WidgetGalleryScreenState extends State<WidgetGalleryScreen> {
  String _t(String key) => AppLocalizations.forLanguageCode(widget.language)
      .text(key, domain: 'widgets');

  static const _accentChoices = <(String, Color)>[
    ('blue', Color(0xFF168CFF)),
    ('cyan', Color(0xFF00BCD4)),
    ('purple', Color(0xFF7B2CBF)),
    ('green', Color(0xFF16A36A)),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(title: Text(_t('widgets'))),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final customization = controller.widgetCustomization;
          final accent = Color(customization.accentColor);
          final progress = customization.dataPeriod == 'weekly'
              ? controller.consistencyPercent(7) / 100
              : controller.dailyProgress(DateTime.now());
          final weekPercent = controller.consistencyPercent(7);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
            children: [
              Text(
                _t('galleryDescription'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: WidgetCustomization.styles.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.9,
                ),
                itemBuilder: (context, index) {
                  final style = WidgetCustomization.styles[index];
                  final selected = style == customization.style;
                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _update(customization.copyWith(style: style)),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? accent
                              : theme.colorScheme.outlineVariant,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: _widgetPreview(
                              style: style,
                              accent: accent,
                              progress: progress,
                              weekPercent: weekPercent,
                              compact: customization.compact,
                              dark: customization.theme == 'dark' ||
                                  (customization.theme == 'system' &&
                                      theme.brightness == Brightness.dark),
                              showProgress: customization.showProgress,
                              showTasks: customization.showTasks,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _t(style),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (selected)
                                Icon(Icons.check_circle,
                                    color: accent, size: 18),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('customize'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Wrap(
                          spacing: 12,
                          children: [
                            for (final (name, color) in _accentChoices)
                              Tooltip(
                                message: _t(name),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => _update(
                                    customization.copyWith(
                                      accentColor: color.toARGB32(),
                                    ),
                                  ),
                                  child: CircleAvatar(
                                    radius: 19,
                                    backgroundColor: color,
                                    child: customization.accentColor ==
                                            color.toARGB32()
                                        ? const Icon(
                                            Icons.check,
                                            color: Colors.white,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                            value: 'system',
                            label: Text(_t('system')),
                          ),
                          ButtonSegment(
                            value: 'light',
                            label: Text(_t('light')),
                          ),
                          ButtonSegment(
                            value: 'dark',
                            label: Text(_t('dark')),
                          ),
                        ],
                        selected: {customization.theme},
                        onSelectionChanged: (value) => _update(
                          customization.copyWith(theme: value.first),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_t('compact')),
                        value: customization.compact,
                        onChanged: (value) => _update(
                          customization.copyWith(compact: value),
                        ),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_t('showProgress')),
                        value: customization.showProgress,
                        onChanged: (value) => _update(
                          customization.copyWith(showProgress: value),
                        ),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_t('showTasks')),
                        value: customization.showTasks,
                        onChanged: (value) => _update(
                          customization.copyWith(showTasks: value),
                        ),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: customization.dataPeriod,
                        decoration:
                            InputDecoration(labelText: _t('dataPeriod')),
                        items: [
                          DropdownMenuItem(
                            value: 'daily',
                            child: Text(_t('daily')),
                          ),
                          DropdownMenuItem(
                            value: 'weekly',
                            child: Text(_t('weekly')),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            _update(
                              customization.copyWith(dataPeriod: value),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _requestWidget,
                          icon: const Icon(Icons.add_to_home_screen_rounded),
                          label: Text(_t('addToHome')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                _t('widgetPrivacy'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _widgetPreview({
    required String style,
    required Color accent,
    required double progress,
    required int weekPercent,
    required bool compact,
    required bool dark,
    required bool showProgress,
    required bool showTasks,
  }) {
    final background = dark ? const Color(0xFF151C2C) : Colors.white;
    final foreground = dark ? const Color(0xFFF8FAFC) : const Color(0xFF172033);
    final muted = dark ? const Color(0xFF94A3B8) : const Color(0xFF667085);
    final tasks =
        widget.controller.tasksForDay(DateTime.now()).take(3).toList();
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 9 : 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: switch (style) {
        'dailyProgress' => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _previewHeader(foreground, muted, accent, _t('today')),
              const Spacer(),
              Row(
                children: [
                  _progressRing(progress, accent, foreground),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${widget.controller.completedCount(DateTime.now())}/${widget.controller.taskCount(DateTime.now())} ${_t('done')}',
                      style: TextStyle(color: foreground, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          ),
        'morningRoutine' => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _previewHeader(
                foreground,
                muted,
                const Color(0xFFFFA726),
                _t('morning'),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _previewTasks(
                  tasks
                      .where((task) => task.period == RoutinePeriod.morning)
                      .toList(),
                  foreground,
                  muted,
                  accent,
                  showTasks,
                ),
              ),
            ],
          ),
        'eveningRoutine' => Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF26335A), Color(0xFF171D35)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(11),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _previewHeader(
                  Colors.white,
                  const Color(0xFFB8C2DC),
                  const Color(0xFFB39DFF),
                  _t('evening'),
                ),
                const Spacer(),
                Text(
                  showTasks ? _t('windDown') : _t('reminder'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _t('gentleRoutine'),
                  style: const TextStyle(
                    color: Color(0xFFB8C2DC),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        'weeklyRoutine' => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _previewHeader(foreground, muted, accent, _t('weekly')),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(7, (index) {
                  final start = RoutineController.weekStart(DateTime.now());
                  final dailyProgress = widget.controller.dailyProgress(
                    start.add(Duration(days: index)),
                  );
                  final height = 13.0 + dailyProgress * 29;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Container(
                        height: height,
                        decoration: BoxDecoration(
                          color: accent.withValues(
                            alpha: dailyProgress > 0 ? 0.95 : 0.2,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 7),
              Text(
                '$weekPercent% ${_t('consistency')}',
                style: TextStyle(color: foreground, fontSize: 10),
              ),
            ],
          ),
        'minimal' => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${(progress * 100).round()}%',
                  style: TextStyle(
                    color: accent,
                    fontSize: compact ? 26 : 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(_t('today'), style: TextStyle(color: muted, fontSize: 10)),
                if (showProgress) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: progress,
                    color: accent,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ],
              ],
            ),
          ),
        'statistics' => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _previewHeader(foreground, muted, accent, _t('stats')),
              const Spacer(),
              Text(
                '${widget.controller.currentStreak}',
                style: TextStyle(
                  color: accent,
                  fontSize: 29,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(_t('dayStreak'),
                  style: TextStyle(color: muted, fontSize: 10)),
              const SizedBox(height: 6),
              if (showProgress)
                LinearProgressIndicator(
                  value: weekPercent / 100,
                  color: accent,
                  borderRadius: BorderRadius.circular(5),
                ),
            ],
          ),
        _ => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _previewHeader(foreground, muted, accent, _t('quickActions')),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _actionPreview(Icons.water_drop_outlined, accent, foreground),
                  _actionPreview(Icons.wb_sunny_outlined, accent, foreground),
                  _actionPreview(Icons.check_rounded, accent, foreground),
                ],
              ),
              if (showTasks)
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(
                    tasks.isEmpty ? _t('noTasks') : tasks.first.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted, fontSize: 9),
                  ),
                ),
            ],
          ),
      },
    );
  }

  Widget _previewHeader(
    Color foreground,
    Color muted,
    Color accent,
    String label,
  ) =>
      Row(
        children: [
          Icon(Icons.spa_rounded, size: 14, color: accent),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Icon(Icons.more_horiz, size: 14, color: muted),
        ],
      );

  Widget _progressRing(double progress, Color accent, Color foreground) =>
      SizedBox(
        width: 43,
        height: 43,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: progress,
              strokeWidth: 4,
              color: accent,
              backgroundColor: accent.withValues(alpha: 0.15),
            ),
            Text(
              '${(progress * 100).round()}%',
              style: TextStyle(
                color: foreground,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );

  Widget _previewTasks(
    List<RoutineTask> tasks,
    Color foreground,
    Color muted,
    Color accent,
    bool showTasks,
  ) {
    if (!showTasks) {
      return Text(
        _t('morning'),
        style: TextStyle(color: muted, fontSize: 10),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final task in tasks.take(3))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  task.isCompletedOn(DateTime.now())
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 12,
                  color: accent,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: foreground, fontSize: 9),
                  ),
                ),
              ],
            ),
          ),
        if (tasks.isEmpty)
          Text(_t('noTasks'), style: TextStyle(color: muted, fontSize: 9)),
      ],
    );
  }

  Widget _actionPreview(IconData icon, Color accent, Color foreground) =>
      Container(
        width: 29,
        height: 29,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 16, color: accent),
      );

  Future<void> _update(WidgetCustomization customization) async {
    try {
      await widget.controller.saveWidgetCustomization(customization);
    } on Exception catch (error) {
      if (mounted) _showNotice('${_t('saveFailed')}: $error');
    }
  }

  Future<void> _requestWidget() async {
    try {
      final requested = await widget.controller.requestPinWidget();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_t('addToHome')),
          content:
              Text(_t(requested ? 'pinRequested' : 'manualPinInstructions')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_t('ok')),
            ),
          ],
        ),
      );
    } on Exception catch (error) {
      if (mounted) _showNotice('${_t('pinFailed')}: $error');
    }
  }

  void _showNotice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

const _weekdayKeys = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];
