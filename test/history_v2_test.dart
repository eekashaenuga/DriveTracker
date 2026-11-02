import 'package:flutter_test/flutter_test.dart';
import 'package:drivetracker/features/daily_records/domain/history_filter.dart';
import 'package:drivetracker/features/daily_records/domain/history_page.dart';
import 'package:drivetracker/features/daily_records/domain/daily_activity.dart';
import 'package:drivetracker/features/daily_records/domain/income_activity.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:drivetracker/core/calculations/analytics_date_range.dart';

import 'helpers/test_services.dart';

void main() {
  Future<(TestServices, String)> fixture() async {
    final s = createTestServices();
    final v = await s.vehicleService.addVehicle(
      const VehicleDraft(
        name: 'Fiesta',
        make: 'Ford',
        model: 'Fiesta',
        fuelType: FuelType.petrol,
        distanceUnit: DistanceUnit.miles,
        currentOdometer: 1000,
      ),
    );
    final db = await s.database.database;
    await db.transaction((txn) async {
      for (var n = 0; n < 237; n++) {
        final date = DateTime.utc(2026, 10, 1 + n % 3).toIso8601String();
        await txn.insert('expenses', {
          'id': 'e${n.toString().padLeft(3, '0')}',
          'vehicle_id': v.id,
          'category_id': 'cat_expense_parking',
          'event_datetime': date,
          'amount_minor': n + 1,
          'merchant': n == 0 ? '100% literal_under!' : 'ordinary',
          'created_at': date,
          'updated_at': date,
        });
      }
      final date = DateTime.utc(2026, 10, 2).toIso8601String();
      for (final t in IncomeActivityType.values) {
        await txn.insert('income_records', {
          'id': t.name,
          'vehicle_id': v.id,
          'category_id': 'cat_income_delivery',
          'event_datetime': date,
          'amount_minor': 1000,
          'activity_type': t.name,
          'created_at': date,
          'updated_at': date,
        });
      }
    });
    return (s, v.id);
  }

  for (final preset in AnalyticsRangePreset.values.where(
    (p) => p != AnalyticsRangePreset.custom,
  )) {
    test(
      'calendar preset ${preset.name} paging matches complete range',
      () async {
        final (s, id) = await fixture();
        final now = DateTime(2026, 10, 2, 12);
        final f = HistoryFilter(
          vehicleIds: [id],
          range: AnalyticsDateRange.preset(preset),
        );
        final complete = await s.activities.search(f, now: now);
        final page = await s.activities.page(f, now: now, pageSize: 200);
        expect(
          page.records.map((r) => r.recordId),
          complete.take(200).map((r) => r.recordId),
        );
        expect(
          page.records.every(
            (r) => f.range.resolve(now).contains(r.eventDateTime),
          ),
          isTrue,
        );
      },
    );
  }
  test('different filters start independent cursors including archived category and Unicode', () async {
    final (s, id) = await fixture();
    final db = await s.database.database;
    await db.update(
      'record_categories',
      {'is_archived': 1, 'name': 'Parking café'},
      where: 'id = ?',
      whereArgs: ['cat_expense_parking'],
    );
    final f = HistoryFilter(
      vehicleIds: [id],
      type: DailyActivityType.expense,
      categoryId: 'cat_expense_parking',
      searchQuery: 'café',
    );
    final first = await s.activities.page(f, pageSize: 20);
    expect(first.records, hasLength(20));
    expect(first.records.every((r) => r.title == 'Parking café'), isTrue);
    expect(
      (await s.activities.page(f.copyWith(searchQuery: '100%')))
          .records
          .single
          .recordId,
      'e000',
    );
    expect(
      (await s.activities.page(f.copyWith(type: DailyActivityType.income)))
          .records,
      isEmpty,
    );
    expect(
      (await s.activities.page(f.copyWith(vehicleId: 'missing'))).records,
      isEmpty,
    );
  });
  for (final sort in HistorySort.values) {
    test(
      'keyset ${sort.name}: complete traversal ties no duplicates gaps and final partial page',
      () async {
        final (s, id) = await fixture();
        final f = HistoryFilter(vehicleId: id, sort: sort);
        final rows = <DailyActivity>[];
        HistoryCursor? cursor;
        do {
          final page = await s.activities.page(f, after: cursor, pageSize: 17);
          rows.addAll(page.records);
          cursor = page.next;
        } while (cursor != null);
        expect(rows, hasLength(243));
        expect(
          rows.map((r) => '${r.type.name}/${r.recordId}').toSet(),
          hasLength(243),
        );
        final complete = await s.activities.search(
          HistoryFilter(vehicleIds: [id], sort: sort),
        );
        expect(rows.map((r) => r.recordId), complete.map((r) => r.recordId));
        final again = await s.activities.page(f, pageSize: 17);
        expect(
          again.records.map((r) => r.recordId),
          rows.take(17).map((r) => r.recordId),
        );
      },
    );
  }
  for (final search in ['100%', 'literal_', 'under!', 'ORDINARY']) {
    test('literal substring and case-insensitive search: $search', () async {
      final (s, id) = await fixture();
      final page = await s.activities.page(
        HistoryFilter(vehicleId: id, searchQuery: search),
      );
      expect(page.records.length, search == 'ORDINARY' ? 50 : 1);
      if (search != 'ORDINARY') expect(page.records.single.recordId, 'e000');
    });
  }
  for (final t in IncomeActivityType.values) {
    test('saved activity display label ${t.label}', () async {
      final (s, id) = await fixture();
      final page = await s.activities.page(
        HistoryFilter(vehicleId: id, searchQuery: t.label),
      );
      expect(page.records.map((r) => r.recordId), [t.name]);
    });
  }
  test('category date type activity and explicit scopes intersect', () async {
    final (s, id) = await fixture();
    final f = HistoryFilter(
      vehicleIds: [id],
      recordTypes: const {DailyActivityType.income},
      activityTypes: const {IncomeActivityType.delivery},
      selectedActivityType: IncomeActivityType.rideshare,
      range: AnalyticsDateRange.custom(
        start: DateTime(2026, 10, 2),
        endInclusive: DateTime(2026, 10, 2),
      ),
    );
    expect((await s.activities.page(f)).records, isEmpty);
    final narrowed = f.copyWith(
      selectedActivityType: IncomeActivityType.delivery,
      categoryId: 'cat_income_delivery',
    );
    expect(
      (await s.activities.page(narrowed)).records.single.recordId,
      'delivery',
    );
    expect(
      (await s.activities.page(
        narrowed.copyWith(type: DailyActivityType.expense),
      )).records,
      isEmpty,
    );
  });
}
