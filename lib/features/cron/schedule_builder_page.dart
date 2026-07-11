import 'package:flutter/material.dart';

import 'cron_validator.dart';

/// Full-page schedule builder that returns a job configuration map.
///
/// Replaces the old raw-text schedule dialog with a structured, safe UI:
/// - Mode selection (one-time, hourly, daily, weekdays, weekly, custom cron)
/// - Time + day pickers
/// - Timezone selector
/// - Natural-language preview
/// - Next 3 run times
/// - Inline validation
/// - Consequence explanation (agent vs script, notification behavior)
class ScheduleBuilderPage extends StatefulWidget {
  final String actionLabel;

  // Pre-fill for edit mode.
  final String initialName;
  final String initialPrompt;
  final String initialSchedule;
  final bool initialNoAgent;
  final String? initialTimezone;

  const ScheduleBuilderPage({
    required this.actionLabel,
    super.key,
    this.initialName = '',
    this.initialPrompt = '',
    this.initialSchedule = '',
    this.initialNoAgent = false,
    this.initialTimezone,
  });

  @override
  State<ScheduleBuilderPage> createState() => _ScheduleBuilderPageState();
}

class _ScheduleBuilderPageState extends State<ScheduleBuilderPage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _promptCtrl;
  late final TextEditingController _cronCtrl;

  late ScheduleMode _mode;
  int _hour = 9;
  int _minute = 0;
  int _hourlyStep = 2;
  int _weeklyDow = 1; // Monday
  DateTime _oneTimeDate = DateTime.now().add(const Duration(hours: 1));
  String _timezoneId;
  bool _noAgent = false;
  String? _scheduleError;
  String _naturalPreview = '';
  List<DateTime> _nextRuns = [];

  _ScheduleBuilderPageState()
      : _timezoneId = TimezoneOption.deviceTimezoneId;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _promptCtrl = TextEditingController(text: widget.initialPrompt);
    _cronCtrl = TextEditingController(text: '');
    _noAgent = widget.initialNoAgent;
    _timezoneId = widget.initialTimezone ?? TimezoneOption.deviceTimezoneId;

    // Try to detect mode from existing schedule.
    if (widget.initialSchedule.isNotEmpty) {
      _mode = CronValidator.detectMode(widget.initialSchedule);
      if (_mode != ScheduleMode.oneTime && _mode != ScheduleMode.custom) {
        final time = CronValidator.extractTime(widget.initialSchedule);
        if (time != null) {
          _hour = time.hour;
          _minute = time.minute;
        }
        if (_mode == ScheduleMode.weekly) {
          final dow = CronValidator.extractDayOfWeek(widget.initialSchedule);
          if (dow != null) _weeklyDow = dow;
        }
        if (_mode == ScheduleMode.hourly) {
          final step = CronValidator.extractHourlyStep(widget.initialSchedule);
          if (step != null && step > 0) _hourlyStep = step;
        }
      } else if (_mode == ScheduleMode.custom) {
        _cronCtrl.text = widget.initialSchedule;
      }
    } else {
      _mode = ScheduleMode.daily;
    }

    _updatePreview();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _promptCtrl.dispose();
    _cronCtrl.dispose();
    super.dispose();
  }

  String _buildSchedule() {
    switch (_mode) {
      case ScheduleMode.oneTime:
        return CronValidator.buildOneTime(_oneTimeDate);
      case ScheduleMode.hourly:
        return CronValidator.buildHourly(_hourlyStep);
      case ScheduleMode.daily:
        return CronValidator.buildDaily(_hour, _minute);
      case ScheduleMode.weekdays:
        return CronValidator.buildWeekdays(_hour, _minute);
      case ScheduleMode.weekly:
        return CronValidator.buildWeekly(_weeklyDow, _hour, _minute);
      case ScheduleMode.custom:
        return _cronCtrl.text.trim();
    }
  }

  void _updatePreview() {
    final schedule = _buildSchedule();
    String? error;
    String preview = '';
    List<DateTime> runs = [];

    if (schedule.isEmpty) {
      error = 'Schedule is required';
    } else if (_mode == ScheduleMode.custom) {
      final result = CronValidator.validate(schedule);
      if (!result.valid) {
        error = result.error;
      } else {
        preview = CronValidator.describe(schedule, timezone: _tzLabel);
        runs = CronValidator.nextRuns(schedule, count: 3);
      }
    } else if (_mode == ScheduleMode.oneTime) {
      if (_oneTimeDate.isBefore(DateTime.now())) {
        error = 'Selected time is in the past';
      } else {
        preview = 'Once at ${_formatDateTime(_oneTimeDate)}, $_tzLabel';
        runs = [_oneTimeDate];
      }
    } else {
      final result = CronValidator.validate(schedule);
      if (!result.valid) {
        error = result.error;
      } else {
        preview = CronValidator.describe(schedule, timezone: _tzLabel);
        runs = CronValidator.nextRuns(schedule, count: 3);
      }
    }

    setState(() {
      _scheduleError = error;
      _naturalPreview = preview;
      _nextRuns = runs;
    });
  }

  String get _tzLabel {
    final tz = TimezoneOption.findById(_timezoneId);
    return tz?.label ?? _timezoneId;
  }

  String _formatDateTime(DateTime dt) {
    final d = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final t = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$d $t';
  }

  String _formatRun(DateTime dt) {
    final now = DateTime.now();
    final diff = dt.difference(now);
    String relative;
    if (diff.inHours < 1) {
      relative = 'in ${diff.inMinutes} min';
    } else if (diff.inDays < 1) {
      relative = 'in ${diff.inHours} h';
    } else {
      relative = 'in ${diff.inDays} d';
    }
    final d = '${dt.month}/${dt.day}';
    final t = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$d $t ($relative)';
  }

  bool get _isFormValid {
    if (_nameCtrl.text.trim().isEmpty) return false;
    if (_promptCtrl.text.trim().isEmpty) return false;
    return _scheduleError == null;
  }

  void _submit() {
    if (!_isFormValid) return;

    Navigator.pop(context, {
      'name': _nameCtrl.text.trim(),
      'prompt': _promptCtrl.text.trim(),
      'schedule': _buildSchedule(),
      'no_agent': _noAgent,
      'timezone': _timezoneId,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.actionLabel == 'Add' ? 'New Automation' : 'Edit Automation'),
        actions: [
          TextButton(
            onPressed: _isFormValid ? _submit : null,
            child: Text(widget.actionLabel),
          ),
        ],
      ),
      body: Form(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Name ──────────────────────────────────────────────
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g., Daily backup',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // ── Prompt ────────────────────────────────────────────
            TextField(
              controller: _promptCtrl,
              decoration: const InputDecoration(
                labelText: 'Prompt',
                hintText: 'What should the agent do?',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),

            // ── Schedule mode selector ────────────────────────────
            Text('Schedule', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _buildModeSelector(theme),
            const SizedBox(height: 16),

            // ── Mode-specific config ──────────────────────────────
            _buildModeConfig(theme),
            const SizedBox(height: 16),

            // ── Timezone ──────────────────────────────────────────
            _buildTimezoneSelector(theme),
            const SizedBox(height: 20),

            // ── Preview card ──────────────────────────────────────
            _buildPreviewCard(theme),
            const SizedBox(height: 16),

            // ── Next runs ─────────────────────────────────────────
            if (_nextRuns.isNotEmpty) _buildNextRunsCard(theme),

            // ── Agent vs script ───────────────────────────────────
            const SizedBox(height: 16),
            _buildAgentToggle(theme),
            const SizedBox(height: 12),

            // ── Consequences ──────────────────────────────────────
            _buildConsequencesCard(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSelector(ThemeData theme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ScheduleMode.values.map((mode) {
        final selected = _mode == mode;
        return ChoiceChip(
          label: Text(_modeLabel(mode)),
          selected: selected,
          onSelected: (_) {
            setState(() => _mode = mode);
            _updatePreview();
          },
        );
      }).toList(),
    );
  }

  String _modeLabel(ScheduleMode mode) {
    switch (mode) {
      case ScheduleMode.oneTime:
        return 'One-time';
      case ScheduleMode.hourly:
        return 'Hourly';
      case ScheduleMode.daily:
        return 'Daily';
      case ScheduleMode.weekdays:
        return 'Weekdays';
      case ScheduleMode.weekly:
        return 'Weekly';
      case ScheduleMode.custom:
        return 'Custom cron';
    }
  }

  Widget _buildModeConfig(ThemeData theme) {
    switch (_mode) {
      case ScheduleMode.oneTime:
        return _buildOneTimeConfig(theme);
      case ScheduleMode.hourly:
        return _buildHourlyConfig(theme);
      case ScheduleMode.daily:
        return _buildTimeConfig(theme);
      case ScheduleMode.weekdays:
        return _buildTimeConfig(theme);
      case ScheduleMode.weekly:
        return _buildWeeklyConfig(theme);
      case ScheduleMode.custom:
        return _buildCustomCronConfig(theme);
    }
  }

  Widget _buildOneTimeConfig(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Run once at', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text('${_oneTimeDate.year}-${_oneTimeDate.month.toString().padLeft(2, '0')}-${_oneTimeDate.day.toString().padLeft(2, '0')}'),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _oneTimeDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() {
                          _oneTimeDate = DateTime(
                            picked.year,
                            picked.month,
                            picked.day,
                            _oneTimeDate.hour,
                            _oneTimeDate.minute,
                          );
                        });
                        _updatePreview();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.access_time, size: 18),
                    label: Text('${_oneTimeDate.hour.toString().padLeft(2, '0')}:${_oneTimeDate.minute.toString().padLeft(2, '0')}'),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(hour: _oneTimeDate.hour, minute: _oneTimeDate.minute),
                      );
                      if (picked != null) {
                        setState(() {
                          _oneTimeDate = DateTime(
                            _oneTimeDate.year,
                            _oneTimeDate.month,
                            _oneTimeDate.day,
                            picked.hour,
                            picked.minute,
                          );
                        });
                        _updatePreview();
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHourlyConfig(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text('Run every', style: theme.textTheme.bodyMedium),
            const SizedBox(width: 12),
            DropdownButton<int>(
              value: _hourlyStep,
              items: [1, 2, 3, 4, 6, 8, 12].map((n) {
                return DropdownMenuItem(value: n, child: Text('$n h'));
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _hourlyStep = value);
                  _updatePreview();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeConfig(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text('Run at', style: theme.textTheme.bodyMedium),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.access_time, size: 18),
              label: Text(CronValidator.formatTime(_hour, _minute)),
              onPressed: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: _hour, minute: _minute),
                );
                if (picked != null) {
                  setState(() {
                    _hour = picked.hour;
                    _minute = picked.minute;
                  });
                  _updatePreview();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyConfig(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Day of week', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: List.generate(7, (i) {
                final dow = i == 6 ? 0 : i + 1; // Mon=1..Sat=6, Sun=0
                final selected = _weeklyDow == dow;
                return ChoiceChip(
                  label: Text(CronValidator.dayNames[i]),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _weeklyDow = dow);
                    _updatePreview();
                  },
                );
              }),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Run at', style: theme.textTheme.bodyMedium),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.access_time, size: 18),
                  label: Text(CronValidator.formatTime(_hour, _minute)),
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(hour: _hour, minute: _minute),
                    );
                    if (picked != null) {
                      setState(() {
                        _hour = picked.hour;
                        _minute = picked.minute;
                      });
                      _updatePreview();
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomCronConfig(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _cronCtrl,
              decoration: InputDecoration(
                labelText: 'Cron expression',
                hintText: 'min hour dom month dow',
                border: const OutlineInputBorder(),
                errorText: _scheduleError,
                helperText: '5 fields: minute hour day-of-month month day-of-week',
              ),
              style: const TextStyle(fontFamily: 'monospace'),
              onChanged: (_) => _updatePreview(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                ActionChip(
                  label: const Text('0 9 * * *'),
                  onPressed: () { _cronCtrl.text = '0 9 * * *'; _updatePreview(); },
                ),
                ActionChip(
                  label: const Text('*/15 * * * *'),
                  onPressed: () { _cronCtrl.text = '*/15 * * * *'; _updatePreview(); },
                ),
                ActionChip(
                  label: const Text('0 */6 * * *'),
                  onPressed: () { _cronCtrl.text = '0 */6 * * *'; _updatePreview(); },
                ),
                ActionChip(
                  label: const Text('0 9 * * 1-5'),
                  onPressed: () { _cronCtrl.text = '0 9 * * 1-5'; _updatePreview(); },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimezoneSelector(ThemeData theme) {
    final tz = TimezoneOption.findById(_timezoneId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.public, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Timezone', style: theme.textTheme.bodyMedium),
                  Text(
                    tz?.label ?? _timezoneId,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            DropdownButton<String>(
              value: _timezoneId,
              items: TimezoneOption.common.map((t) {
                return DropdownMenuItem(value: t.id, child: Text(t.label));
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _timezoneId = value);
                  _updatePreview();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard(ThemeData theme) {
    final hasError = _scheduleError != null;
    return Card(
      color: hasError
          ? Colors.red.withValues(alpha: 0.08)
          : theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasError ? Icons.error_outline : Icons.preview,
                  size: 20,
                  color: hasError ? Colors.red : theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  hasError ? 'Validation' : 'Preview',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (hasError)
              Text(
                _scheduleError!,
                style: TextStyle(color: Colors.red[700], fontSize: 13),
              )
            else if (_naturalPreview.isNotEmpty)
              Text(
                _naturalPreview,
                style: theme.textTheme.bodyLarge,
              )
            else
              Text(
                'Enter schedule details to see a preview.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            if (!hasError && _mode != ScheduleMode.custom && _mode != ScheduleMode.oneTime) ...[
              const SizedBox(height: 6),
              Text(
                'Cron: ${_buildSchedule()}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNextRunsCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Next ${_nextRuns.length} runs', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            for (final run in _nextRuns)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.arrow_forward, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 8),
                    Text(_formatRun(run), style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentToggle(ThemeData theme) {
    return Card(
      child: SwitchListTile(
        title: const Text('Script only (no agent)'),
        subtitle: const Text('Use for cron jobs backed by scripts, not the AI agent.'),
        value: _noAgent,
        onChanged: (value) => setState(() => _noAgent = value),
      ),
    );
  }

  Widget _buildConsequencesCard(ThemeData theme) {
    final isAgent = !_noAgent;
    return Card(
      color: isAgent
          ? Colors.orange.withValues(alpha: 0.06)
          : Colors.blue.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isAgent ? Icons.psychology : Icons.terminal,
                  size: 20,
                  color: isAgent ? Colors.orange[700] : Colors.blue[700],
                ),
                const SizedBox(width: 8),
                Text(
                  isAgent ? 'Agent-based job' : 'Script-only job',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: isAgent ? Colors.orange[700] : Colors.blue[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _consequenceRow(
              'Execution',
              isAgent
                  ? 'The AI agent will process the prompt. This may take several minutes and consume API credits.'
                  : 'A pre-configured script runs without invoking the agent. Faster and no API cost.',
            ),
            const SizedBox(height: 6),
            _consequenceRow(
              'Notifications',
              isAgent
                  ? 'You will be notified when the agent completes or if it fails.'
                  : 'You will be notified of script success or failure.',
            ),
            const SizedBox(height: 6),
            _consequenceRow(
              'Trigger now',
              isAgent
                  ? 'Triggering now will start an agent session immediately. Confirm before running expensive jobs.'
                  : 'Triggering now will run the script immediately.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _consequenceRow(String label, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ),
        Expanded(
          child: Text(
            description,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ),
      ],
    );
  }
}
