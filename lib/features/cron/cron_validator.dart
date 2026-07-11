/// Schedule modes supported by the builder.
enum ScheduleMode {
  oneTime,
  hourly,
  daily,
  weekdays,
  weekly,
  custom,
}

/// Result of validating a cron expression.
class CronValidationResult {
  final bool valid;
  final String? error;
  final List<int> minutes;
  final List<int> hours;
  final List<int> daysOfMonth;
  final List<int> months;
  final List<int> daysOfWeek;

  const CronValidationResult({
    required this.valid,
    this.error,
    this.minutes = const [],
    this.hours = const [],
    this.daysOfMonth = const [],
    this.months = const [],
    this.daysOfWeek = const [],
  });

  static const invalid = CronValidationResult(valid: false, error: 'Invalid');
}

/// Parsed cron expression with helpers for preview and next-run computation.
class CronValidator {
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _dayNamesFull = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// Validate a 5-field cron expression.
  static CronValidationResult validate(String expr) {
    final parts = expr.trim().split(RegExp(r'\s+'));
    if (parts.length != 5) {
      return const CronValidationResult(
        valid: false,
        error: 'Cron expression must have exactly 5 fields: min hour dom month dow',
      );
    }

    try {
      final minutes = _parseField(parts[0], 0, 59);
      final hours = _parseField(parts[1], 0, 23);
      final daysOfMonth = _parseField(parts[2], 1, 31);
      final months = _parseField(parts[3], 1, 12);
      final daysOfWeek = _parseField(parts[4], 0, 6);

      if (minutes.isEmpty || hours.isEmpty || daysOfMonth.isEmpty ||
          months.isEmpty || daysOfWeek.isEmpty) {
        return const CronValidationResult(
          valid: false,
          error: 'One or more fields resolved to no values',
        );
      }

      return CronValidationResult(
        valid: true,
        minutes: minutes,
        hours: hours,
        daysOfMonth: daysOfMonth,
        months: months,
        daysOfWeek: daysOfWeek,
      );
    } on _CronParseError catch (e) {
      return CronValidationResult(valid: false, error: e.message);
    }
  }

  static List<int> _parseField(String field, int min, int max) {
    final result = <int>{};

    for (final part in field.split(',')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;

      int step = 1;
      String rangePart = trimmed;

      if (trimmed.contains('/')) {
        final slashParts = trimmed.split('/');
        if (slashParts.length != 2) {
          throw _CronParseError('Invalid step syntax: $trimmed');
        }
        step = int.tryParse(slashParts[1]) ?? -1;
        if (step <= 0) {
          throw _CronParseError('Step must be a positive integer: $trimmed');
        }
        rangePart = slashParts[0];
      }

      int rangeMin, rangeMax;

      if (rangePart == '*') {
        rangeMin = min;
        rangeMax = max;
      } else if (rangePart.contains('-')) {
        final rangeParts = rangePart.split('-');
        if (rangeParts.length != 2) {
          throw _CronParseError('Invalid range: $rangePart');
        }
        rangeMin = int.tryParse(rangeParts[0].trim()) ?? -1;
        rangeMax = int.tryParse(rangeParts[1].trim()) ?? -1;
        if (rangeMin < min || rangeMax > max || rangeMin > rangeMax) {
          throw _CronParseError('Range out of bounds: $rangePart (valid $min-$max)');
        }
      } else {
        final val = int.tryParse(rangePart) ?? -1;
        if (val < min || val > max) {
          throw _CronParseError('Value out of bounds: $rangePart (valid $min-$max)');
        }
        rangeMin = val;
        rangeMax = val;
      }

      for (int v = rangeMin; v <= rangeMax; v += step) {
        result.add(v);
      }
    }

    return result.toList()..sort();
  }

  /// Generate a natural-language description from a cron expression.
  static String describe(String expr, {String? timezone}) {
    final result = validate(expr);
    if (!result.valid) return expr;

    final buf = StringBuffer();
    final tzLabel = timezone != null && timezone.isNotEmpty ? ', $timezone' : '';

    // Check for common patterns.
    if (_isEveryNHours(result)) {
      final step = _detectHourlyStep(result);
      if (step == 1) {
        buf.write('Every hour$tzLabel');
      } else {
        buf.write('Every $step hours$tzLabel');
      }
      return buf.toString();
    }

    if (_isDaily(result)) {
      final h = result.hours.first;
      final m = result.minutes.first;
      buf.write('Daily at ${_formatTime(h, m)}$tzLabel');
      return buf.toString();
    }

    if (_isWeekdays(result)) {
      final h = result.hours.first;
      final m = result.minutes.first;
      buf.write('Every weekday at ${_formatTime(h, m)}$tzLabel');
      return buf.toString();
    }

    if (_isWeekly(result)) {
      final h = result.hours.first;
      final m = result.minutes.first;
      final dow = result.daysOfWeek.first;
      buf.write('Every ${_dayNamesFull[dow]} at ${_formatTime(h, m)}$tzLabel');
      return buf.toString();
    }

    // Fallback: describe the full expression.
    final timeParts = <String>[];
    if (result.minutes.length <= 4) {
      for (final m in result.minutes) {
        for (final h in result.hours) {
          timeParts.add(_formatTime(h, m));
        }
      }
    }

    if (timeParts.isNotEmpty && timeParts.length <= 4) {
      buf.write('At ${timeParts.join(", ")}');
    } else if (result.hours.length == 1 && result.minutes.length == 1) {
      buf.write('At ${_formatTime(result.hours.first, result.minutes.first)}');
    } else {
      buf.write('Custom schedule');
    }

    final dayParts = <String>[];
    if (result.daysOfWeek.length < 7) {
      for (final d in result.daysOfWeek) {
        dayParts.add(_dayNames[d]);
      }
      buf.write(' on ${dayParts.join(", ")}');
    }

    buf.write(tzLabel);
    return buf.toString();
  }

  static bool _isEveryNHours(CronValidationResult r) {
    return r.minutes.length == 1 &&
        r.minutes.first == 0 &&
        r.hours.length > 1 &&
        r.daysOfMonth.length == 31 &&
        r.months.length == 12 &&
        r.daysOfWeek.length == 7;
  }

  static int _detectHourlyStep(CronValidationResult r) {
    if (r.hours.length < 2) return 1;
    final step = r.hours[1] - r.hours[0];
    // Verify uniform step.
    for (int i = 1; i < r.hours.length; i++) {
      if (r.hours[i] - r.hours[i - 1] != step) return -1;
    }
    return step;
  }

  static bool _isDaily(CronValidationResult r) {
    return r.minutes.length == 1 &&
        r.hours.length == 1 &&
        r.daysOfMonth.length == 31 &&
        r.months.length == 12 &&
        r.daysOfWeek.length == 7;
  }

  static bool _isWeekdays(CronValidationResult r) {
    return r.minutes.length == 1 &&
        r.hours.length == 1 &&
        r.daysOfMonth.length == 31 &&
        r.months.length == 12 &&
        r.daysOfWeek.length == 5 &&
        r.daysOfWeek.first == 1 &&
        r.daysOfWeek.last == 5;
  }

  static bool _isWeekly(CronValidationResult r) {
    return r.minutes.length == 1 &&
        r.hours.length == 1 &&
        r.daysOfMonth.length == 31 &&
        r.months.length == 12 &&
        r.daysOfWeek.length == 1;
  }

  static String _formatTime(int hour, int minute) {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Compute the next [count] run times from [from] (defaults to now).
  /// Returns empty list if the expression is invalid or no runs within 365 days.
  static List<DateTime> nextRuns(String expr, {DateTime? from, int count = 3}) {
    final result = validate(expr);
    if (!result.valid) return [];

    final start = (from ?? DateTime.now()).add(const Duration(minutes: 1));
    final runs = <DateTime>[];
    final limit = start.add(const Duration(days: 365));

    var candidate = DateTime(start.year, start.month, start.day, start.hour, start.minute);

    while (candidate.isBefore(limit) && runs.length < count) {
      if (_matches(result, candidate)) {
        runs.add(candidate);
      }
      candidate = candidate.add(const Duration(minutes: 1));
    }

    return runs;
  }

  static bool _matches(CronValidationResult r, DateTime dt) {
    if (!r.minutes.contains(dt.minute)) return false;
    if (!r.hours.contains(dt.hour)) return false;
    if (!r.months.contains(dt.month)) return false;

    // Cron: if both dom and dow are restricted, match either.
    final domRestricted = r.daysOfMonth.length < 31;
    final dowRestricted = r.daysOfWeek.length < 7;

    if (domRestricted && dowRestricted) {
      final dow = dt.weekday == 7 ? 0 : dt.weekday;
      if (!r.daysOfMonth.contains(dt.day) && !r.daysOfWeek.contains(dow)) {
        return false;
      }
    } else if (domRestricted) {
      if (!r.daysOfMonth.contains(dt.day)) return false;
    } else if (dowRestricted) {
      final dow = dt.weekday == 7 ? 0 : dt.weekday;
      if (!r.daysOfWeek.contains(dow)) return false;
    }

    return true;
  }

  // ── Schedule builders ──────────────────────────────────────────────

  static String buildHourly(int everyN) {
    if (everyN <= 1) return '0 * * * *';
    return '0 */$everyN * * *';
  }

  static String buildDaily(int hour, int minute) {
    return '$minute $hour * * *';
  }

  static String buildWeekdays(int hour, int minute) {
    return '$minute $hour * * 1-5';
  }

  static String buildWeekly(int dayOfWeek, int hour, int minute) {
    return '$minute $hour * * $dayOfWeek';
  }

  static String buildOneTime(DateTime dt) {
    return dt.toUtc().toIso8601String();
  }

  /// Try to detect the schedule mode from an existing cron expression.
  static ScheduleMode detectMode(String schedule) {
    final result = validate(schedule);
    if (!result.valid) return ScheduleMode.custom;

    if (_isEveryNHours(result)) return ScheduleMode.hourly;
    if (_isDaily(result)) return ScheduleMode.daily;
    if (_isWeekdays(result)) return ScheduleMode.weekdays;
    if (_isWeekly(result)) return ScheduleMode.weekly;

    return ScheduleMode.custom;
  }

  /// Try to extract hour and minute from a cron expression.
  static ({int hour, int minute})? extractTime(String expr) {
    final result = validate(expr);
    if (!result.valid || result.hours.length != 1 || result.minutes.length != 1) {
      return null;
    }
    return (hour: result.hours.first, minute: result.minutes.first);
  }

  /// Try to extract the day-of-week from a weekly cron expression.
  static int? extractDayOfWeek(String expr) {
    final result = validate(expr);
    if (!result.valid || result.daysOfWeek.length != 1) return null;
    return result.daysOfWeek.first;
  }

  /// Try to extract the hourly step from an hourly cron expression.
  static int? extractHourlyStep(String expr) {
    final result = validate(expr);
    if (!result.valid || !_isEveryNHours(result)) return null;
    return _detectHourlyStep(result);
  }

  static const dayNames = _dayNames;
  static const dayNamesFull = _dayNamesFull;

  static String formatTime(int hour, int minute) => _formatTime(hour, minute);
}

class _CronParseError implements Exception {
  final String message;
  _CronParseError(this.message);
}

/// Common timezones for the selector.
class TimezoneOption {
  final String id;
  final String label;
  final Duration offset;

  const TimezoneOption(this.id, this.label, this.offset);

  static const utc = TimezoneOption('UTC', 'UTC', Duration.zero);

  static const common = [
    utc,
    TimezoneOption('America/New_York', 'Eastern (ET)', Duration(hours: -5)),
    TimezoneOption('America/Chicago', 'Central (CT)', Duration(hours: -6)),
    TimezoneOption('America/Denver', 'Mountain (MT)', Duration(hours: -7)),
    TimezoneOption('America/Los_Angeles', 'Pacific (PT)', Duration(hours: -8)),
    TimezoneOption('Europe/London', 'London (GMT/BST)', Duration.zero),
    TimezoneOption('Europe/Jerusalem', 'Jerusalem (IST)', Duration(hours: 2)),
    TimezoneOption('Europe/Paris', 'Central European (CET)', Duration(hours: 1)),
    TimezoneOption('Asia/Tokyo', 'Tokyo (JST)', Duration(hours: 9)),
    TimezoneOption('Asia/Shanghai', 'China (CST)', Duration(hours: 8)),
    TimezoneOption('Asia/Kolkata', 'India (IST)', Duration(hours: 5, minutes: 30)),
    TimezoneOption('Australia/Sydney', 'Sydney (AEDT)', Duration(hours: 11)),
  ];

  static TimezoneOption? findById(String id) {
    try {
      return common.firstWhere((tz) => tz.id == id);
    } catch (_) {
      return null;
    }
  }

  static String get deviceTimezoneId {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    try {
      return common.firstWhere((tz) => tz.offset == offset).id;
    } catch (_) {
      return 'UTC';
    }
  }
}
