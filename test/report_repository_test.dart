import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drivetracker/features/reports/data/report_repository.dart';
import 'package:drivetracker/features/reports/domain/report_request.dart';
import 'package:drivetracker/features/insights/data/insights_repository.dart';
import 'package:drivetracker/features/daily_records/domain/income_earnings.dart';
import 'package:drivetracker/features/daily_records/domain/income_activity.dart';
import 'package:drivetracker/core/calculations/analytics_date_range.dart';

import 'helpers/report_fixture.dart';

void main() {
  test(
    'requested vehicle remains exact with multiple active vehicles',
    () async {
      final (s, id) = await reportFixture();
      final other = await s.vehicleService.addVehicle(
        const VehicleDraft(
          name: 'Other',
          currentOdometer: 1000,
          make: 'Kia',
          model: 'Rio',
          fuelType: FuelType.diesel,
          distanceUnit: DistanceUnit.kilometers,
        ),
      );
      final db = await s.database.database;
      final at = DateTime(2026, 10, 2).toUtc().toIso8601String();
      await db.insert('expenses', {
        'id': 'other',
        'vehicle_id': other.id,
        'category_id': 'cat_expense_parking',
        'event_datetime': at,
        'amount_minor': 99999,
        'created_at': at,
        'updated_at': at,
      });
      final d = await ReportRepository(
        s.database,
        clock: () => reportNow,
      ).load(reportRequest(id));
      expect(d.vehicleName, 'My Fiesta');
      expect(d.metrics['expenses']!.value, 300);
      expect(
        d.tables
            .singleWhere((t) => t.name == 'Expenses')
            .rows
            .any((r) => r.last == 'other'),
        isFalse,
      );
    },
  );
  test('empty selection still yields canonical summary and immutable transient request', () async {
    final (s, id) = await reportFixture();
    final sections = <ReportSection>{};
    final request = reportRequest(id, sections: sections);
    sections.add(ReportSection.documents);
    final d = await ReportRepository(
      s.database,
      clock: () => reportNow,
    ).load(request);
    expect(d.tables, isEmpty);
    expect(d.metrics['gross']!.value, 1000);
    expect(
      () => request.sections.add(ReportSection.fuel),
      throwsUnsupportedError,
    );
  });
  test(
    'unknown acquisition date follows canonical bounded and all-time rules',
    () async {
      final (s, id) = await reportFixture();
      final db = await s.database.database;
      await db.update(
        'vehicles',
        {'purchase_date': null},
        where: 'id = ?',
        whereArgs: [id],
      );
      final repository = ReportRepository(s.database, clock: () => reportNow);
      final bounded = await repository.load(reportRequest(id));
      final all = await repository.load(
        reportRequest(id, range: AnalyticsDateRange.all),
      );
      expect(bounded.metrics['acquisition']!.value, 0);
      expect(bounded.metrics['undated']!.value, 1);
      expect(all.metrics['acquisition']!.value, 250000);
    },
  );

  for (final complete in [false, true]) {
    test('canonical parity completeness=$complete', () async {
      final (s, id) = await reportFixture(complete: complete);
      final request = reportRequest(id);
      final data = await ReportRepository(
        s.database,
        clock: () => reportNow,
      ).load(request);
      final expected = await InsightsRepository(s.database)
          .loadInsights(vehicleId: id, range: request.range, now: reportNow);
      final driving = EarningsSummary(
        expected.incomeActivities.where(
          (r) =>
              r.activity.type == IncomeActivityType.delivery ||
              r.activity.type == IncomeActivityType.rideshare,
        ),
      );
      expect(data.metrics['operating']!.value, expected.totalSpendMinor);
      expect(data.metrics['fuel']!.value, expected.fuelSpendMinor);
      expect(data.metrics['service']!.value, expected.serviceSpendMinor);
      expect(data.metrics['expenses']!.value, expected.expenseSpendMinor);
      expect(data.metrics['acquisition']!.value, expected.acquisitionCostMinor);
      expect(data.metrics['ownership']!.value, expected.ownershipSpendMinor);
      expect(
        data.metrics['volume']!.value,
        expected.fuelVolumeMillilitres / 1000,
      );
      expect(
        data.metrics['price']!.value,
        expected.averageFuelPriceMicrosPerLitre! / 10000,
      );
      expect(data.metrics['economy']!.value, expected.averageFuelEconomy.ukMpg);
      expect(
        data.metrics['economy']!.note,
        contains(
          '${expected.averageFuelEconomy.intervalCount} completed intervals',
        ),
      );
      expect(data.metrics['distance']!.value, expected.distance.value);
      expect(
        data.metrics['costDistance']!.value,
        expected.totalCostMinorPerDistance,
      );
      expect(data.metrics['gross']!.value, driving.grossMinor);
      expect(data.metrics['gross']!.value, 1000);
      expect(data.metrics['allIncome']!.value, 2000);
      expect(data.metrics['linked']!.value, 250);
      expect(data.metrics['net']!.value, driving.netMinor);
      expect(
        data.metrics['distanceRate']!.value,
        driving.perDistance(expected.scope.distanceUnit!),
      );
      expect(data.metrics['hourRate']!.value, driving.perHour());
      expect(data.metrics['deliveryRate']!.value, driving.perDelivery);
      expect(
        data.metrics['netHourRate']!.value,
        complete ? driving.perHour(net: true) : null,
      );
    });
  }
  test(
    'period details cross-period linked context and baselines remain distinct',
    () async {
      final (s, id) = await reportFixture();
      final d = await ReportRepository(
        s.database,
        clock: () => reportNow,
      ).load(reportRequest(id));
      final expenses = d.tables.singleWhere((t) => t.name == 'Expenses');
      expect(expenses.rows, hasLength(3));
      expect(expenses.rows.every((r) => r[2] == 'Yes'), isTrue);
      final links = d.tables.singleWhere((t) => t.name == 'Linked Costs');
      expect(links.rows.single[1], 'outside');
      expect(links.rows.single.last, 'Yes');
      final services = d.tables.singleWhere((t) => t.name == 'Services');
      expect(services.rows.singleWhere((r) => r.last == 'baseline')[5], isNull);
      expect(
        d.tables.singleWhere((t) => t.name == 'Service Items').rows,
        hasLength(2),
      );
      expect(
        d.tables.singleWhere((t) => t.name == 'Documents').rows.single[4],
        'Due date',
      );
    },
  );
  for (final range in [
    AnalyticsDateRange.all,
    AnalyticsDateRange.custom(
      start: DateTime(2026, 10, 2),
      endInclusive: DateTime(2026, 10, 2),
    ),
    AnalyticsDateRange.custom(
      start: DateTime(2026, 9, 1),
      endInclusive: DateTime(2026, 9, 1),
    ),
  ]) {
    test('calendar scope ${range.preset} ${range.customStart}', () async {
      final (s, id) = await reportFixture();
      final d = await ReportRepository(
        s.database,
        clock: () => reportNow,
      ).load(reportRequest(id, range: range));
      final expected = await InsightsRepository(s.database)
          .loadInsights(vehicleId: id, range: range, now: reportNow);
      expect(d.metrics['acquisition']!.value, expected.acquisitionCostMinor);
      expect(d.metrics['ownership']!.value, expected.ownershipSpendMinor);
      expect(
        d.tables
            .singleWhere((t) => t.name == 'Expenses')
            .rows
            .every(
              (r) => range.resolve(reportNow).contains(r.first as DateTime),
            ),
        isTrue,
      );
    });
  }
  test('more than 200 source rows and no source mutation', () async {
    final (s, id) = await reportFixture(expenses: 251);
    final db = await s.database.database;
    final before = await db.rawQuery('SELECT * FROM expenses ORDER BY id');
    final d = await ReportRepository(
      s.database,
      clock: () => reportNow,
    ).load(reportRequest(id));
    expect(
      d.tables.singleWhere((t) => t.name == 'Expenses').rows,
      hasLength(251),
    );
    expect(await db.rawQuery('SELECT * FROM expenses ORDER BY id'), before);
    expect(() => d.tables.first.rows.add([]), throwsUnsupportedError);
    expect(() => d.metrics.clear(), throwsUnsupportedError);
  });
  for (final sensitive in [false, true]) {
    test('sensitive data explicit inclusion $sensitive', () async {
      final (s, id) = await reportFixture();
      final d = await ReportRepository(
        s.database,
        clock: () => reportNow,
      ).load(reportRequest(id, sensitive: sensitive));
      expect(d.identity.any((m) => m.value == 'PRIVATE-VIN'), sensitive);
      final doc = d.tables
          .singleWhere((t) => t.name == 'Documents')
          .rows
          .single;
      expect(doc[6], sensitive ? 'PRIVATE-POLICY' : null);
      expect(doc[7], sensitive ? 'PRIVATE-DOC-NOTES' : null);
    });
  }
  test(
    'section choices and archived vehicle are read-only; missing vehicle fails',
    () async {
      final (s, id) = await reportFixture();
      await s.vehicleService.archiveVehicle(id);
      final repository = ReportRepository(s.database, clock: () => reportNow);
      final d = await repository.load(
        reportRequest(id, sections: {ReportSection.fuel}),
      );
      expect(d.tables.map((t) => t.name), ['Fuel']);
      expect(
        d.identity.singleWhere((m) => m.label == 'Archived vehicle').value,
        'Yes',
      );
      expect(
        () => repository.load(reportRequest('missing')),
        throwsA(isA<ReportException>()),
      );
    },
  );
}
