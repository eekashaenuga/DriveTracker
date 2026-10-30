import 'package:flutter_test/flutter_test.dart';
import 'package:drivetracker/core/calculations/analytics_date_range.dart';

void main() {
  test('calendar presets, year rollover and all time', () {
    final now = DateTime(2026, 1, 15, 12);
    for (final row in [
      (AnalyticsRangePreset.month, DateTime(2026, 1), DateTime(2026, 2)),
      (AnalyticsRangePreset.lastMonth, DateTime(2025, 12), DateTime(2026, 1)),
      (
        AnalyticsRangePreset.lastThreeMonths,
        DateTime(2025, 11),
        DateTime(2026, 2),
      ),
      (AnalyticsRangePreset.year, DateTime(2026, 1), DateTime(2027, 1)),
    ]) {
      final range = AnalyticsDateRange.preset(row.$1).resolve(now);
      expect(range.startInclusive, row.$2);
      expect(range.endExclusive, row.$3);
      final buckets = range.buckets();
      expect(buckets.first.startInclusive, row.$2);
      expect(buckets.last.endExclusive, row.$3);
      for (var n = 1; n < buckets.length; n++) {
        expect(buckets[n].startInclusive, buckets[n - 1].endExclusive);
      }
    }
    expect(AnalyticsDateRange.all.resolve(now).isBounded, isFalse);
    expect(AnalyticsDateRange.all.resolve(now).buckets(), isEmpty);
  });
  test('weekly History behavior is retained at autumn DST', () {
    final range = AnalyticsDateRange.week.resolve(
      DateTime(2026, 10, 25, 23, 30),
    );
    expect(range.startInclusive, DateTime(2026, 10, 19));
    expect(range.endExclusive, DateTime(2026, 10, 26));
    expect(range.buckets(), hasLength(7));
  });
  for (final day in [DateTime(2026, 3, 29), DateTime(2026, 10, 25)]) {
    test('custom local calendar end and daily buckets across DST $day', () {
      final range = AnalyticsDateRange.custom(
        start: day,
        endInclusive: day,
      ).resolve(day);
      expect(range.endExclusive, DateTime(day.year, day.month, day.day + 1));
      expect(
        range.contains(DateTime(day.year, day.month, day.day, 23, 59)),
        isTrue,
      );
      expect(
        range.contains(DateTime(day.year, day.month, day.day + 1)),
        isFalse,
      );
      final buckets = range.buckets();
      expect(buckets, hasLength(1));
      expect(buckets.single.endExclusive, range.endExclusive);
    });
  }
}
