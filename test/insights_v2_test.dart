import 'package:drivetracker/features/odometer/domain/odometer_entry.dart';
import 'package:drivetracker/features/insights/presentation/insight_visuals.dart';
import 'package:drivetracker/features/daily_records/domain/expense.dart';
import 'package:drivetracker/features/daily_records/domain/income.dart';
import 'package:drivetracker/features/daily_records/domain/income_activity.dart';
import 'package:drivetracker/features/daily_records/domain/income_earnings.dart';
import 'package:drivetracker/features/daily_records/domain/history_filter.dart';
import 'package:drivetracker/features/daily_records/domain/daily_activity.dart';
import 'package:drivetracker/features/daily_records/data/activity_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drivetracker/core/calculations/analytics_date_range.dart';
import 'package:drivetracker/features/daily_records/domain/refuel.dart';
import 'package:drivetracker/features/daily_records/domain/fuel_economy_calculator.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';

import 'helpers/test_services.dart';

Refuel fill(
  String id,
  int odo,
  int ml, {
  bool full = true,
  bool missed = false,
  int day = 1,
}) => Refuel(
  id: id,
  vehicleId: 'v',
  eventDateTime: DateTime(2026, 1, day),
  odometer: odo,
  fuelType: FuelType.petrol,
  totalCostMinor: ml,
  volumeMillilitres: ml,
  unitPriceMicrosPerLitre: 1000000,
  isFullTank: full,
  missedPreviousRefuel: missed,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
void main() {
  test('litre-based full-fill records never manufacture EV efficiency', () {
    final electric = [
      for (final r in [fill('a', 1000, 50000), fill('b', 1400, 40000, day: 2)])
        Refuel.fromMap({
          ...r.toMap(),
          'fuel_type': FuelType.electric.storageValue,
        }),
    ];
    expect(
      FuelEconomyCalculator.validIntervals(
        refuels: electric,
        distanceUnit: DistanceUnit.kilometers,
      ),
      isEmpty,
    );
  });

  test('aligned calendar-boundary observations allow a cost rate without interpolation', () async {
    final s = createTestServices();
    final v = await s.vehicleService.addVehicle(
      const VehicleDraft(
        name: 'Car',
        make: 'Ford',
        model: 'Focus',
        fuelType: FuelType.petrol,
        distanceUnit: DistanceUnit.miles,
        currentOdometer: 1000,
      ),
    );
    for (final row in [
      ('start', DateTime(2026, 1, 1), 1000),
      ('end', DateTime(2026, 2, 1), 1500),
    ]) {
      await s.odometers.insert(
        OdometerEntry(
          id: row.$1,
          vehicleId: v.id,
          odometer: row.$3,
          eventDateTime: row.$2,
          sourceType: OdometerSourceType.manual,
          createdAt: row.$2,
          updatedAt: row.$2,
        ),
      );
    }
    await s.expenseService.createExpense(
      ExpenseDraft(
        vehicleId: v.id,
        categoryId: 'cat_expense_parking',
        eventDateTime: DateTime(2026, 1, 15),
        amountMinor: 5001,
      ),
    );
    final result = await s.insights.loadInsights(
      vehicleId: v.id,
      range: AnalyticsDateRange.custom(
        start: DateTime(2026, 1, 1),
        endInclusive: DateTime(2026, 1, 31),
      ),
    );
    expect(result.costDistanceAligned, isTrue);
    expect(result.distance.value, 500);
    expect(result.totalCostMinorPerDistance, 10.002);
  });

  test('fuel observations use elapsed dates, not equal index spacing', () {
    final points = [
      for (final d in [1, 2, 11])
        DTInsightLinePoint(
          date: DateTime(2026, 1, d),
          label: '$d',
          value: 1,
          valueLabel: '1',
          detailLabel: '$d',
          semanticsLabel: '$d',
        ),
    ];
    expect(insightDateFraction(points, 0), 0);
    expect(insightDateFraction(points, 1), 0.1);
    expect(insightDateFraction(points, 2), 1);
  });
  test('cross-range fuel interval includes partial fuel but excludes opening volume', () async {
    final s = createTestServices();
    final v = await s.vehicleService.addVehicle(
      const VehicleDraft(
        name: 'Car',
        make: 'Ford',
        model: 'Focus',
        fuelType: FuelType.petrol,
        distanceUnit: DistanceUnit.kilometers,
        currentOdometer: 1000,
      ),
    );
    final db = await s.database.database;
    for (final r in [
      fill('open', 1000, 60000),
      fill('partial', 1200, 10000, full: false, day: 2),
      fill('close', 1500, 30000, day: 3),
    ]) {
      await db.insert('refuels', {...r.toMap(), 'vehicle_id': v.id});
    }
    final result = await s.insights.loadInsights(
      vehicleId: v.id,
      range: AnalyticsDateRange.custom(
        start: DateTime(2026, 1, 3),
        endInclusive: DateTime(2026, 1, 3),
      ),
    );
    expect(result.fuelVolumeMillilitres, 30000);
    expect(result.fuelSpendMinor, 30000);
    expect(result.averageFuelEconomy.volumeMillilitres, 40000);
    expect(result.averageFuelEconomy.distance, 500);
    expect(
      result.averageFuelEconomy.ukMpg,
      closeTo((500 / 1.609344) / (40 * 0.219969), 0.00001),
    );
    expect(result.averageFuelEconomy.start, DateTime(2026, 1, 1).toUtc());
    expect(result.fuelPriceTrend.single.date, DateTime(2026, 1, 3).toUtc());
  });

  test('first full, partial chains, missed history and non-increasing boundaries stay conservative', () {
    final records = [
      fill('ignored-partial', 900, 5000, full: false),
      fill('a', 1000, 60000),
      fill('b', 1200, 10000, full: false, day: 2),
      fill('c', 1400, 20000, day: 3),
    ];
    final intervals = FuelEconomyCalculator.validIntervals(
      refuels: records,
      distanceUnit: DistanceUnit.miles,
    );
    expect(intervals.single.distance, 400);
    expect(intervals.single.volumeMillilitres, 30000);
    final reset = FuelEconomyCalculator.validIntervals(
      refuels: [
        fill('a', 1000, 50000),
        fill('b', 1400, 40000, missed: true, day: 2),
        fill('c', 1800, 30000, day: 3),
      ],
      distanceUnit: DistanceUnit.miles,
    );
    expect(reset.single.startRefuel.id, 'b');
    expect(reset.single.distance, 400);
    for (final end in [1000, 900]) {
      expect(
        FuelEconomyCalculator.validIntervals(
          refuels: [fill('a', 1000, 50000), fill('b', end, 40000, day: 2)],
          distanceUnit: DistanceUnit.miles,
        ),
        isEmpty,
      );
    }
  });
  test('activity rates match eligible numerators and unknown costs never become net', () {
    IncomeEarnings record(String id, int gross, IncomeActivity a, int costs) =>
        IncomeEarnings(
          Income(
            id: id,
            vehicleId: 'v',
            categoryId: 'cat_income_delivery',
            eventDateTime: DateTime(2026),
            amountMinor: gross,
            activity: a,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
          costs,
        );
    final summary = EarningsSummary([
      record(
        'a',
        10000,
        const IncomeActivity(
          type: IncomeActivityType.delivery,
          durationMinutes: 60,
          distanceMm: 16093440,
          deliveryCount: 2,
          directCostsComplete: true,
        ),
        12000,
      ),
      record(
        'b',
        20000,
        const IncomeActivity(
          type: IncomeActivityType.delivery,
          durationMinutes: 180,
          directCostsComplete: true,
        ),
        0,
      ),
      record('c', 90000, const IncomeActivity(), 0),
    ]);
    expect(summary.grossMinor, 120000);
    expect(summary.perHour(), 7500);
    expect(summary.perDistance(DistanceUnit.miles), 1000);
    expect(summary.perDelivery, 5000);
    expect(summary.netMinor, isNull);
    expect(summary.records.first.netMinor, -2000);
    expect(summary.durationCount, 2);
  });
  test('History drill-through keeps active vehicle set, costs and activity types exact', () async {
    final s = createTestServices();
    final vehicles = [];
    for (final name in ['A', 'B', 'Archived']) {
      final v = await s.vehicleService.addVehicle(
        VehicleDraft(
          name: name,
          make: 'Ford',
          model: 'Focus',
          fuelType: FuelType.petrol,
          distanceUnit: DistanceUnit.miles,
          currentOdometer: 1000,
        ),
      );
      vehicles.add(v);
      await s.expenseService.createExpense(
        ExpenseDraft(
          vehicleId: v.id,
          categoryId: 'cat_expense_parking',
          eventDateTime: DateTime(2026, 1, 5),
          amountMinor: 501,
        ),
      );
      await s.incomeService.createIncome(
        IncomeDraft(
          vehicleId: v.id,
          categoryId: 'cat_income_delivery',
          eventDateTime: DateTime(2026, 1, 6),
          amountMinor: 1000,
          activity: const IncomeActivity(type: IncomeActivityType.delivery),
        ),
      );
      await s.incomeService.createIncome(
        IncomeDraft(
          vehicleId: v.id,
          categoryId: 'cat_income_other',
          eventDateTime: DateTime(2026, 1, 6),
          amountMinor: 777,
        ),
      );
    }
    await s.vehicleService.archiveVehicle(vehicles.last.id);
    final result = await s.insights.loadInsights(
      vehicleId: null,
      range: AnalyticsDateRange.all,
    );
    expect(result.totalSpendMinor, 1002);
    final db = await s.database.database;
    final at = DateTime(2026, 1, 7).toUtc().toIso8601String();
    await db.insert('services', {
      'id': 'baseline',
      'vehicle_id': vehicles.first.id,
      'event_datetime': at,
      'total_cost_minor': 999,
      'is_baseline': 1,
      'created_at': at,
      'updated_at': at,
    });
    final repository = ActivityRepository(s.database);
    final costs = await repository.search(
      HistoryFilter(
        vehicleIds: result.vehicleIds,
        recordTypes: const {
          DailyActivityType.expense,
          DailyActivityType.refuel,
          DailyActivityType.service,
        },
        operatingCostsOnly: true,
      ),
    );
    expect(costs, hasLength(2));
    expect(
      costs.fold<int>(0, (s, r) => s + r.amountMinor!),
      result.totalSpendMinor,
    );
    final income = await repository.search(
      HistoryFilter(
        vehicleIds: result.vehicleIds,
        type: DailyActivityType.income,
        activityTypes: const {IncomeActivityType.delivery},
      ),
    );
    expect(income, hasLength(2));
    expect(income.every((r) => r.amountMinor == 1000), isTrue);
    expect(
      (await repository.search(const HistoryFilter()))
          .any((r) => r.vehicleId == vehicles.last.id),
      isTrue,
      reason: 'Ordinary History defaults stay unchanged',
    );
    await db.transaction((txn) async {
      for (var n = 0; n < 250; n++) {
        await txn.insert('expenses', {
          'id': 'many_$n',
          'vehicle_id': vehicles.first.id,
          'category_id': 'cat_expense_parking',
          'event_datetime': at,
          'amount_minor': 1,
          'created_at': at,
          'updated_at': at,
        });
      }
    });
    expect(
      await repository.search(
        HistoryFilter(
          vehicleIds: result.vehicleIds,
          recordTypes: const {DailyActivityType.expense},
          operatingCostsOnly: true,
        ),
      ),
      hasLength(252),
    );
    expect(
      await repository.search(
        const HistoryFilter(type: DailyActivityType.expense),
      ),
      hasLength(200),
    );
  });

  test('shared economy supports kilometres with weighted interval totals', () {
    final intervals = FuelEconomyCalculator.validIntervals(
      refuels: [
        fill('a', 1000, 60000),
        fill('b', 1200, 10000, full: false, day: 2),
        fill('c', 1500, 30000, day: 3),
      ],
      distanceUnit: DistanceUnit.kilometers,
    );
    expect(intervals, hasLength(1));
    expect(intervals.single.volumeMillilitres, 40000);
    expect(
      intervals.single.ukMpg,
      closeTo((500 / 1.609344) / (40 * 0.219969), 0.00001),
    );
  });
  test(
    'bounded spend never divides by distance extending outside its coverage',
    () async {
      final s = createTestServices();
      final v = await s.vehicleService.addVehicle(
        const VehicleDraft(
          name: 'Car',
          make: 'Ford',
          model: 'Focus',
          fuelType: FuelType.petrol,
          distanceUnit: DistanceUnit.miles,
          currentOdometer: 1000,
        ),
      );
      await s.refuelService.createRefuel(
        RefuelDraft(
          vehicleId: v.id,
          eventDateTime: DateTime(2026, 1, 15),
          odometer: 1500,
          fuelType: FuelType.petrol,
          totalCostMinor: 5000,
          volumeMillilitres: 40000,
          unitPriceMicrosPerLitre: 1250000,
          isFullTank: true,
          missedPreviousRefuel: false,
        ),
      );
      final result = await s.insights.loadInsights(
        vehicleId: v.id,
        range: AnalyticsDateRange.custom(
          start: DateTime(2026, 1, 1),
          endInclusive: DateTime(2026, 1, 31),
        ),
      );
      expect(result.fuelSpendMinor, 5000);
      expect(result.fuelCostMinorPerDistance, isNull);
    },
  );
}
