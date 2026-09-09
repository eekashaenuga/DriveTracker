enum AnalyticsRangePreset {
  week('Week'),
  month('Month'),
  year('Year'),
  all('All'),
  custom('Custom');

  const AnalyticsRangePreset(this.label);

  final String label;
}

enum AnalyticsBucketSize { day, week, month, year }

class AnalyticsDateRange {
  const AnalyticsDateRange.preset(this.preset)
    : customStart = null,
      customEndInclusive = null;

  AnalyticsDateRange.custom({
    required DateTime start,
    required DateTime endInclusive,
  }) : preset = AnalyticsRangePreset.custom,
       customStart = _localDay(start),
       customEndInclusive = _localDay(endInclusive) {
    if (_localDay(endInclusive).isBefore(_localDay(start))) {
      throw ArgumentError('Custom range start must be before or equal to end.');
    }
  }

  final AnalyticsRangePreset preset;
  final DateTime? customStart;
  final DateTime? customEndInclusive;

  static const all = AnalyticsDateRange.preset(AnalyticsRangePreset.all);
  static const week = AnalyticsDateRange.preset(AnalyticsRangePreset.week);
  static const month = AnalyticsDateRange.preset(AnalyticsRangePreset.month);
  static const year = AnalyticsDateRange.preset(AnalyticsRangePreset.year);

  ResolvedAnalyticsRange resolve(DateTime now) {
    final localNow = now.toLocal();
    final today = _localDay(localNow);
    return switch (preset) {
      AnalyticsRangePreset.week => ResolvedAnalyticsRange(
        preset: preset,
        startInclusive: today.subtract(Duration(days: today.weekday - 1)),
        endExclusive: today
            .subtract(Duration(days: today.weekday - 1))
            .add(const Duration(days: 7)),
      ),
      AnalyticsRangePreset.month => ResolvedAnalyticsRange(
        preset: preset,
        startInclusive: DateTime(localNow.year, localNow.month),
        endExclusive: DateTime(localNow.year, localNow.month + 1),
      ),
      AnalyticsRangePreset.year => ResolvedAnalyticsRange(
        preset: preset,
        startInclusive: DateTime(localNow.year),
        endExclusive: DateTime(localNow.year + 1),
      ),
      AnalyticsRangePreset.all => const ResolvedAnalyticsRange(
        preset: AnalyticsRangePreset.all,
      ),
      AnalyticsRangePreset.custom => ResolvedAnalyticsRange(
        preset: preset,
        startInclusive: customStart,
        endExclusive: customEndInclusive?.add(const Duration(days: 1)),
      ),
    };
  }

  bool get isCustom => preset == AnalyticsRangePreset.custom;

  @override
  bool operator ==(Object other) {
    return other is AnalyticsDateRange &&
        other.preset == preset &&
        other.customStart == customStart &&
        other.customEndInclusive == customEndInclusive;
  }

  @override
  int get hashCode => Object.hash(preset, customStart, customEndInclusive);

  static DateTime _localDay(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}

class ResolvedAnalyticsRange {
  const ResolvedAnalyticsRange({
    required this.preset,
    this.startInclusive,
    this.endExclusive,
  });

  final AnalyticsRangePreset preset;
  final DateTime? startInclusive;
  final DateTime? endExclusive;

  bool get isBounded => startInclusive != null && endExclusive != null;

  bool contains(DateTime eventDateTime) {
    final local = eventDateTime.toLocal();
    final start = startInclusive;
    final end = endExclusive;
    if (start != null && local.isBefore(start)) {
      return false;
    }
    if (end != null && !local.isBefore(end)) {
      return false;
    }
    return true;
  }

  DateTime? get endInclusive {
    final end = endExclusive;
    if (end == null) {
      return null;
    }
    return end.subtract(const Duration(days: 1));
  }

  List<AnalyticsTimeBucket> buckets({
    DateTime? earliestEvent,
    DateTime? latestEvent,
    int maxBuckets = 18,
  }) {
    final bounds = _bucketBounds(
      earliestEvent: earliestEvent,
      latestEvent: latestEvent,
    );
    if (bounds == null) {
      return const [];
    }

    final (start, end) = bounds;
    final size = _bucketSize(start, end, maxBuckets: maxBuckets);
    final buckets = <AnalyticsTimeBucket>[];
    var cursor = _floorForSize(start, size);
    if (cursor.isBefore(start) && size == AnalyticsBucketSize.week) {
      cursor = start;
    }
    while (cursor.isBefore(end)) {
      final next = _nextBucket(cursor, size);
      final bucketEnd = next.isAfter(end) ? end : next;
      buckets.add(
        AnalyticsTimeBucket(
          startInclusive: cursor,
          endExclusive: bucketEnd,
          size: size,
          label: _bucketLabel(cursor, bucketEnd, size),
        ),
      );
      cursor = next;
    }
    return buckets;
  }

  (DateTime, DateTime)? _bucketBounds({
    DateTime? earliestEvent,
    DateTime? latestEvent,
  }) {
    final start = startInclusive;
    final end = endExclusive;
    if (start != null && end != null) {
      return (start, end);
    }
    if (earliestEvent == null || latestEvent == null) {
      return null;
    }
    final earliest = _localDay(earliestEvent);
    final latest = _localDay(latestEvent).add(const Duration(days: 1));
    if (!earliest.isBefore(latest)) {
      return null;
    }
    return (earliest, latest);
  }

  AnalyticsBucketSize _bucketSize(
    DateTime start,
    DateTime end, {
    required int maxBuckets,
  }) {
    final days = end.difference(start).inDays;
    var size = switch (preset) {
      AnalyticsRangePreset.week => AnalyticsBucketSize.day,
      AnalyticsRangePreset.month => AnalyticsBucketSize.week,
      AnalyticsRangePreset.year => AnalyticsBucketSize.month,
      AnalyticsRangePreset.all =>
        days <= 370 ? AnalyticsBucketSize.month : AnalyticsBucketSize.year,
      AnalyticsRangePreset.custom =>
        days <= 14
            ? AnalyticsBucketSize.day
            : days <= 100
            ? AnalyticsBucketSize.week
            : days <= 730
            ? AnalyticsBucketSize.month
            : AnalyticsBucketSize.year,
    };
    while (_estimatedBucketCount(start, end, size) > maxBuckets &&
        size != AnalyticsBucketSize.year) {
      size = _largerBucket(size);
    }
    return size;
  }

  static int _estimatedBucketCount(
    DateTime start,
    DateTime end,
    AnalyticsBucketSize size,
  ) {
    return switch (size) {
      AnalyticsBucketSize.day => end.difference(start).inDays,
      AnalyticsBucketSize.week => (end.difference(start).inDays / 7).ceil(),
      AnalyticsBucketSize.month =>
        (end.year - start.year) * 12 + end.month - start.month + 1,
      AnalyticsBucketSize.year => end.year - start.year + 1,
    };
  }

  static AnalyticsBucketSize _largerBucket(AnalyticsBucketSize size) {
    return switch (size) {
      AnalyticsBucketSize.day => AnalyticsBucketSize.week,
      AnalyticsBucketSize.week => AnalyticsBucketSize.month,
      AnalyticsBucketSize.month => AnalyticsBucketSize.year,
      AnalyticsBucketSize.year => AnalyticsBucketSize.year,
    };
  }

  static DateTime _localDay(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static DateTime _floorForSize(DateTime value, AnalyticsBucketSize size) {
    return switch (size) {
      AnalyticsBucketSize.day => DateTime(value.year, value.month, value.day),
      AnalyticsBucketSize.week => DateTime(
        value.year,
        value.month,
        value.day,
      ).subtract(Duration(days: value.weekday - 1)),
      AnalyticsBucketSize.month => DateTime(value.year, value.month),
      AnalyticsBucketSize.year => DateTime(value.year),
    };
  }

  static DateTime _nextBucket(DateTime value, AnalyticsBucketSize size) {
    return switch (size) {
      AnalyticsBucketSize.day => value.add(const Duration(days: 1)),
      AnalyticsBucketSize.week => value.add(const Duration(days: 7)),
      AnalyticsBucketSize.month => DateTime(value.year, value.month + 1),
      AnalyticsBucketSize.year => DateTime(value.year + 1),
    };
  }

  static String _bucketLabel(
    DateTime start,
    DateTime end,
    AnalyticsBucketSize size,
  ) {
    return switch (size) {
      AnalyticsBucketSize.day => '${start.day} ${_monthShort(start.month)}',
      AnalyticsBucketSize.week =>
        '${start.day} ${_monthShort(start.month)}-${end.subtract(const Duration(days: 1)).day} ${_monthShort(end.subtract(const Duration(days: 1)).month)}',
      AnalyticsBucketSize.month => '${_monthShort(start.month)} ${start.year}',
      AnalyticsBucketSize.year => start.year.toString(),
    };
  }

  static String _monthShort(int month) {
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
}

class AnalyticsTimeBucket {
  const AnalyticsTimeBucket({
    required this.startInclusive,
    required this.endExclusive,
    required this.size,
    required this.label,
  });

  final DateTime startInclusive;
  final DateTime endExclusive;
  final AnalyticsBucketSize size;
  final String label;

  bool contains(DateTime eventDateTime) {
    final local = eventDateTime.toLocal();
    return !local.isBefore(startInclusive) && local.isBefore(endExclusive);
  }
}
