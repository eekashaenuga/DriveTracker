import 'package:flutter/material.dart';

import '../../core/calculations/analytics_date_range.dart';

Future<AnalyticsDateRange?> pickAnalyticsDateRange({
  required BuildContext context,
  required AnalyticsDateRange currentRange,
  required DateTime currentDate,
  required Key pickerKey,
  required String helpText,
}) async {
  final picked = await showDateRangePicker(
    context: context,
    initialDateRange: _initialDateRange(currentRange),
    firstDate: DateTime(1900),
    lastDate: DateTime(2100, 12, 31),
    currentDate: _dateOnly(currentDate),
    initialEntryMode: DatePickerEntryMode.calendarOnly,
    helpText: helpText,
    cancelText: 'Cancel',
    saveText: 'Apply',
    builder: (context, child) {
      final theme = Theme.of(context);
      return DatePickerTheme(
        data: DatePickerTheme.of(context).copyWith(
          rangePickerHeaderHeadlineStyle: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          rangePickerHeaderHelpStyle: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        child: KeyedSubtree(
          key: pickerKey,
          child: child ?? const SizedBox.shrink(),
        ),
      );
    },
  );
  if (picked == null) {
    return null;
  }
  return AnalyticsDateRange.custom(
    start: picked.start,
    endInclusive: picked.end,
  );
}

String customAnalyticsRangeLabel(AnalyticsDateRange range) {
  final start = range.customStart;
  final end = range.customEndInclusive;
  if (range.preset != AnalyticsRangePreset.custom ||
      start == null ||
      end == null) {
    return 'Custom';
  }

  if (_isSameLocalDay(start, end)) {
    return _formatDay(start, includeYear: true);
  }

  if (start.year == end.year) {
    return '${_formatDay(start)} - ${_formatDay(end, includeYear: true)}';
  }
  return '${_formatDay(start, includeYear: true)} - ${_formatDay(end, includeYear: true)}';
}

DateTimeRange? _initialDateRange(AnalyticsDateRange range) {
  final start = range.customStart;
  final end = range.customEndInclusive;
  if (range.preset != AnalyticsRangePreset.custom ||
      start == null ||
      end == null) {
    return null;
  }
  return DateTimeRange(start: _dateOnly(start), end: _dateOnly(end));
}

DateTime _dateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

bool _isSameLocalDay(DateTime left, DateTime right) {
  final localLeft = left.toLocal();
  final localRight = right.toLocal();
  return localLeft.year == localRight.year &&
      localLeft.month == localRight.month &&
      localLeft.day == localRight.day;
}

String _formatDay(DateTime value, {bool includeYear = false}) {
  final local = value.toLocal();
  final label = '${local.day} ${_monthShort(local.month)}';
  return includeYear ? '$label ${local.year}' : label;
}

String _monthShort(int month) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return months[month - 1];
}
