import 'package:drivetracker/core/calculations/analytics_date_range.dart';
import 'package:drivetracker/features/daily_records/domain/daily_activity.dart';
import 'package:drivetracker/features/daily_records/domain/expense.dart';
import 'package:drivetracker/features/daily_records/domain/history_filter.dart';
import 'package:drivetracker/features/daily_records/domain/income.dart';
import 'package:drivetracker/features/daily_records/domain/record_category.dart';
import 'package:drivetracker/features/daily_records/domain/refuel.dart';
import 'package:drivetracker/features/maintenance/domain/service_record.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_services.dart';

void main() {
  group('Insights repository', () {
    test('totals real expenditure, income and running costs without double counting', () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(
        _vehicleDraft('Commuter', 1000),
      );
      final otherVehicle = await services.vehicleService.addVehicle(
        _vehicleDraft('Weekend', 1000),
      );
      final insurance = await _category(services, 'cat_expense_insurance');
      final parking = await _category(services, 'cat_expense_parking');
      final incomeCategory = await _category(services, 'cat_income_rideshare');

      await services.refuelService.createRefuel(
        _refuelDraft(
          vehicle.id,
          eventDateTime: DateTime.utc(2026, 9, 4, 8),
          odometer: 1100,
          totalCostMinor: 5000,
          volumeMillilitres: 40000,
          unitPriceMicrosPerLitre: 1250000,
        ),
      );
      await services.serviceRecordService.createServiceRecord(
        ServiceRecordDraft(
          vehicleId: vehicle.id,
          eventDateTime: DateTime.utc(2026, 9, 5, 8),
          odometer: 1200,
          totalCostMinor: 9000,
          garage: 'ABC Garage',
          items: const [ServiceItemDraft(itemName: 'Inspection')],
        ),
      );
      await services.expenseService.createExpense(
        ExpenseDraft(
          vehicleId: vehicle.id,
          categoryId: insurance.id,
          eventDateTime: DateTime.utc(2026, 9, 6, 8),
          amountMinor: 12000,
        ),
      );
      await services.expenseService.createExpense(
        ExpenseDraft(
          vehicleId: vehicle.id,
          categoryId: parking.id,
          eventDateTime: DateTime.utc(2026, 9, 7, 8),
          amountMinor: 1500,
        ),
      );
      await services.incomeService.createIncome(
        IncomeDraft(
          vehicleId: vehicle.id,
          categoryId: incomeCategory.id,
          eventDateTime: DateTime.utc(2026, 9, 8, 8),
          amountMinor: 7000,
        ),
      );
      await services.refuelService.createRefuel(
        _refuelDraft(
          otherVehicle.id,
          eventDateTime: DateTime.utc(2026, 9, 9, 8),
          odometer: 1100,
          totalCostMinor: 9999,
          volumeMillilitres: 1000,
          unitPriceMicrosPerLitre: 99999000,
        ),
      );

      final insights = await services.insights.loadInsights(
        vehicleId: vehicle.id,
        range: AnalyticsDateRange.month,
        now: DateTime.utc(2026, 9, 20, 12),
      );

      expect(insights.fuelSpendMinor, 5000);
      expect(insights.serviceSpendMinor, 9000);
      expect(insights.expenseSpendMinor, 13500);
      expect(insights.totalSpendMinor, 27500);
      expect(insights.incomeMinor, 7000);
      expect(insights.netMinor, -20500);
      expect(insights.runningSpendMinor, 15500);
      expect(
        insights.breakdown.map((item) => item.label),
        containsAll(['Fuel', 'Service', 'Insurance', 'Parking']),
      );
      expect(
        await services.expenses.listForVehicle(vehicle.id),
        hasLength(2),
        reason: 'Service totals must not create duplicate expense records.',
      );
    });

    test(
      'uses event dates for ranges and produces truthful time buckets',
      () async {
        final services = createTestServices();
        final vehicle = await services.vehicleService.addVehicle(
          _vehicleDraft('Commuter', 1000),
        );
        final expenseCategory = await _category(
          services,
          'cat_expense_parking',
        );
        final incomeCategory = await _category(services, 'cat_income_delivery');

        await services.expenseService.createExpense(
          ExpenseDraft(
            vehicleId: vehicle.id,
            categoryId: expenseCategory.id,
            eventDateTime: DateTime.utc(2025, 12, 31, 23),
            amountMinor: 2000,
          ),
        );
        await services.expenseService.createExpense(
          ExpenseDraft(
            vehicleId: vehicle.id,
            categoryId: expenseCategory.id,
            eventDateTime: DateTime.utc(2026, 1, 1, 8),
            amountMinor: 3000,
          ),
        );
        await services.incomeService.createIncome(
          IncomeDraft(
            vehicleId: vehicle.id,
            categoryId: incomeCategory.id,
            eventDateTime: DateTime.utc(2026, 3, 10, 8),
            amountMinor: 4000,
          ),
        );

        final insights = await services.insights.loadInsights(
          vehicleId: vehicle.id,
          range: AnalyticsDateRange.year,
          now: DateTime.utc(2026, 9, 20, 12),
        );

        expect(insights.expenseSpendMinor, 3000);
        expect(insights.incomeMinor, 4000);
        expect(insights.spendingBuckets, hasLength(12));
        expect(insights.spendingBuckets[0].label, 'Jan 2026');
        expect(insights.spendingBuckets[0].totalSpendMinor, 3000);
        expect(insights.spendingBuckets[1].totalSpendMinor, 0);
        expect(insights.spendingBuckets[2].incomeMinor, 4000);
        expect(
          insights.breakdown
              .singleWhere((item) => item.label == 'Parking')
              .amountMinor,
          3000,
        );
      },
    );

    test('calculates defensible distance and ignores non-chronological lower readings', () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(
        _vehicleDraft('Commuter', 1000),
      );
      await services.odometerService.recordManualReading(
        vehicleId: vehicle.id,
        odometer: 1500,
        eventDateTime: DateTime.utc(2026, 1, 20, 8),
      );
      await services.odometerService.recordManualReading(
        vehicleId: vehicle.id,
        odometer: 1100,
        eventDateTime: DateTime.utc(2026, 1, 25, 8),
        allowHistorical: true,
      );

      final insights = await services.insights.loadInsights(
        vehicleId: vehicle.id,
        range: AnalyticsDateRange.custom(
          start: DateTime(2026),
          endInclusive: DateTime(2026, 1, 31),
        ),
        now: DateTime.utc(2026, 9, 20, 12),
      );

      expect(insights.distance.value, 500);
      expect(insights.distance.unit, DistanceUnit.miles);
    });

    test('marks insufficient and zero-distance odometer data unavailable for cost per distance', () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(
        _vehicleDraft('Commuter', 1000),
      );

      final insufficient = await services.insights.loadInsights(
        vehicleId: vehicle.id,
        range: AnalyticsDateRange.all,
        now: DateTime.utc(2026, 9, 20, 12),
      );
      expect(insufficient.distance.value, isNull);
      expect(insufficient.totalCostMinorPerDistance, isNull);

      await services.odometerService.recordManualReading(
        vehicleId: vehicle.id,
        odometer: 1000,
        eventDateTime: DateTime.utc(2026, 1, 2, 8),
      );
      final zeroDistance = await services.insights.loadInsights(
        vehicleId: vehicle.id,
        range: AnalyticsDateRange.all,
        now: DateTime.utc(2026, 9, 20, 12),
      );

      expect(zeroDistance.distance.value, 0);
      expect(zeroDistance.runningCostMinorPerDistance, isNull);
      expect(zeroDistance.totalCostMinorPerDistance, isNull);
    });

    test('uses weighted fuel price and aggregate full-to-full MPG', () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(
        _vehicleDraft('Commuter', 1000),
      );

      await services.refuelService.createRefuel(
        _refuelDraft(
          vehicle.id,
          eventDateTime: DateTime.utc(2026, 9, 1, 8),
          odometer: 1000,
          totalCostMinor: 3000,
          volumeMillilitres: 30000,
          unitPriceMicrosPerLitre: 1000000,
        ),
      );
      await services.refuelService.createRefuel(
        _refuelDraft(
          vehicle.id,
          eventDateTime: DateTime.utc(2026, 9, 10, 8),
          odometer: 1200,
          totalCostMinor: 1200,
          volumeMillilitres: 8000,
          unitPriceMicrosPerLitre: 1500000,
          isFullTank: false,
        ),
      );
      await services.refuelService.createRefuel(
        _refuelDraft(
          vehicle.id,
          eventDateTime: DateTime.utc(2026, 9, 20, 8),
          odometer: 1400,
          totalCostMinor: 3200,
          volumeMillilitres: 32000,
          unitPriceMicrosPerLitre: 1000000,
        ),
      );

      final insights = await services.insights.loadInsights(
        vehicleId: vehicle.id,
        range: AnalyticsDateRange.month,
        now: DateTime.utc(2026, 9, 20, 12),
      );

      expect(insights.averageFuelPriceMicrosPerLitre, 1057143);
      expect(insights.averageFuelEconomy.ukMpg, closeTo(45.46, 0.01));
      expect(insights.averageFuelEconomy.distance, 400);
      expect(insights.averageFuelEconomy.volumeMillilitres, 40000);
    });

    test(
      'fuel economy aggregation resumes after missed refuel history',
      () async {
        final services = createTestServices();
        final vehicle = await services.vehicleService.addVehicle(
          _vehicleDraft('Commuter', 1000),
        );

        await services.refuelService.createRefuel(
          _refuelDraft(
            vehicle.id,
            eventDateTime: DateTime.utc(2026, 9, 1, 8),
            odometer: 1000,
          ),
        );
        await services.refuelService.createRefuel(
          _refuelDraft(
            vehicle.id,
            eventDateTime: DateTime.utc(2026, 9, 10, 8),
            odometer: 1400,
            missedPreviousRefuel: true,
          ),
        );
        await services.refuelService.createRefuel(
          _refuelDraft(
            vehicle.id,
            eventDateTime: DateTime.utc(2026, 9, 20, 8),
            odometer: 1800,
          ),
        );

        final insights = await services.insights.loadInsights(
          vehicleId: vehicle.id,
          range: AnalyticsDateRange.month,
          now: DateTime.utc(2026, 9, 20, 12),
        );

        expect(insights.averageFuelEconomy.distance, 400);
        expect(insights.averageFuelEconomy.volumeMillilitres, 40000);
        expect(insights.averageFuelEconomy.ukMpg, closeTo(45.46, 0.01));
        expect(insights.fuelEconomyTrend, hasLength(1));
      },
    );

    test(
      'all vehicles aggregate spend safely without combining odometers',
      () async {
        final services = createTestServices();
        final first = await services.vehicleService.addVehicle(
          _vehicleDraft('Commuter', 1000),
        );
        final second = await services.vehicleService.addVehicle(
          _vehicleDraft('Weekend', 5000),
        );
        final category = await _category(services, 'cat_expense_parking');

        await services.refuelService.createRefuel(
          _refuelDraft(
            first.id,
            eventDateTime: DateTime.utc(2026, 9, 1, 8),
            odometer: 1100,
            totalCostMinor: 5000,
            volumeMillilitres: 40000,
            unitPriceMicrosPerLitre: 1250000,
          ),
        );
        await services.expenseService.createExpense(
          ExpenseDraft(
            vehicleId: second.id,
            categoryId: category.id,
            eventDateTime: DateTime.utc(2026, 9, 2, 8),
            amountMinor: 2000,
          ),
        );

        final insights = await services.insights.loadInsights(
          vehicleId: null,
          range: AnalyticsDateRange.month,
          now: DateTime.utc(2026, 9, 20, 12),
        );

        expect(insights.scope.isAllVehicles, isTrue);
        expect(insights.totalSpendMinor, 7000);
        expect(insights.distance.value, isNull);
        expect(insights.averageFuelEconomy.ukMpg, isNull);
        expect(insights.averageFuelPriceMicrosPerLitre, 1250000);
      },
    );
  });

  group('History repository filters', () {
    test('filter by type, vehicle, date, category and search', () async {
      final services = createTestServices();
      final first = await services.vehicleService.addVehicle(
        _vehicleDraft('Commuter', 1000),
      );
      final second = await services.vehicleService.addVehicle(
        _vehicleDraft('Weekend', 5000),
      );
      final parking = await _category(services, 'cat_expense_parking');
      final insurance = await _category(services, 'cat_expense_insurance');

      await services.expenseService.createExpense(
        ExpenseDraft(
          vehicleId: first.id,
          categoryId: parking.id,
          eventDateTime: DateTime.utc(2026, 9, 5, 8),
          amountMinor: 1200,
          merchant: 'Station Car Park',
          notes: 'airport run',
        ),
      );
      await services.expenseService.createExpense(
        ExpenseDraft(
          vehicleId: first.id,
          categoryId: insurance.id,
          eventDateTime: DateTime.utc(2026, 8, 5, 8),
          amountMinor: 20000,
          merchant: 'Policy Co',
        ),
      );
      await services.expenseService.createExpense(
        ExpenseDraft(
          vehicleId: second.id,
          categoryId: parking.id,
          eventDateTime: DateTime.utc(2026, 9, 5, 8),
          amountMinor: 3400,
          merchant: 'Other Parking',
        ),
      );

      final filtered = await services.activities.search(
        HistoryFilter(
          vehicleId: first.id,
          type: DailyActivityType.expense,
          range: AnalyticsDateRange.month,
          categoryId: parking.id,
          searchQuery: 'airport',
        ),
        now: DateTime.utc(2026, 9, 20, 12),
      );

      expect(filtered, hasLength(1));
      expect(filtered.single.vehicleId, first.id);
      expect(filtered.single.categoryId, parking.id);
      expect(filtered.single.title, 'Parking');
      expect(filtered.single.subtitle, contains('Station Car Park'));
    });

    test(
      'reset-equivalent default filter returns all selected vehicle types',
      () async {
        final services = createTestServices();
        final vehicle = await services.vehicleService.addVehicle(
          _vehicleDraft('Commuter', 1000),
        );
        final incomeCategory = await _category(services, 'cat_income_delivery');

        await services.refuelService.createRefuel(
          _refuelDraft(
            vehicle.id,
            eventDateTime: DateTime.utc(2026, 9, 4, 8),
            odometer: 1100,
          ),
        );
        await services.incomeService.createIncome(
          IncomeDraft(
            vehicleId: vehicle.id,
            categoryId: incomeCategory.id,
            eventDateTime: DateTime.utc(2026, 9, 5, 8),
            amountMinor: 4500,
          ),
        );

        final activities = await services.activities.search(
          HistoryFilter(vehicleId: vehicle.id),
        );

        expect(
          activities.map((activity) => activity.type),
          containsAll([DailyActivityType.refuel, DailyActivityType.income]),
        );
      },
    );
  });
}

VehicleDraft _vehicleDraft(String name, int odometer) {
  return VehicleDraft(
    name: name,
    make: 'Ford',
    model: 'Focus',
    currentOdometer: odometer,
    fuelType: FuelType.petrol,
    distanceUnit: DistanceUnit.miles,
  );
}

RefuelDraft _refuelDraft(
  String vehicleId, {
  required DateTime eventDateTime,
  required int odometer,
  int totalCostMinor = 5000,
  int volumeMillilitres = 40000,
  int unitPriceMicrosPerLitre = 1250000,
  bool isFullTank = true,
  bool missedPreviousRefuel = false,
}) {
  return RefuelDraft(
    vehicleId: vehicleId,
    eventDateTime: eventDateTime,
    odometer: odometer,
    fuelType: FuelType.petrol,
    totalCostMinor: totalCostMinor,
    volumeMillilitres: volumeMillilitres,
    unitPriceMicrosPerLitre: unitPriceMicrosPerLitre,
    isFullTank: isFullTank,
    missedPreviousRefuel: missedPreviousRefuel,
  );
}

Future<RecordCategory> _category(TestServices services, String id) async {
  final category = await services.categories.getById(id);
  return category ?? fail('Expected seeded category $id.');
}
