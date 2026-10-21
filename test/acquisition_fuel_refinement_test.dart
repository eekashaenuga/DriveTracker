import 'package:drivetracker/core/calculations/analytics_date_range.dart';
import 'package:drivetracker/core/calculations/cost_per_distance.dart';
import 'package:drivetracker/core/utilities/formatters.dart';
import 'package:drivetracker/features/calculator/domain/fuel_calculator.dart';
import 'package:drivetracker/features/daily_records/domain/expense.dart';
import 'package:drivetracker/features/daily_records/domain/refuel.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_services.dart';

VehicleDraft draft({
  double? price,
  DateTime? date,
  DistanceUnit unit = DistanceUnit.miles,
}) => VehicleDraft(
  name: 'Commuter',
  make: 'Ford',
  model: 'Focus',
  fuelType: FuelType.petrol,
  distanceUnit: unit,
  currentOdometer: 1000,
  purchasePrice: price,
  purchaseDate: date,
);

void main() {
  test(
    'acquisition is optional and does not create expenses or operating spend',
    () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(
        draft(price: 3000.55, date: DateTime(2026, 9, 5)),
      );
      final expense = await services.expenseService.createExpense(
        ExpenseDraft(
          vehicleId: vehicle.id,
          categoryId: 'cat_expense_parking',
          eventDateTime: DateTime(2026, 9, 6),
          amountMinor: 1500,
        ),
      );
      final result = await services.insights.loadInsights(
        vehicleId: vehicle.id,
        range: AnalyticsDateRange.month,
        now: DateTime(2026, 9, 20),
      );
      expect(result.acquisitionCostMinor, 300055);
      expect(result.totalSpendMinor, 1500);
      expect(result.runningSpendMinor, 1500);
      expect(result.ownershipSpendMinor, 301555);
      expect(
        result.spendingBuckets.fold<int>(
          0,
          (sum, b) => sum + b.totalSpendMinor,
        ),
        1500,
      );
      expect(result.breakdown, hasLength(1));
      expect(
        (await services.expenses.listForVehicle(vehicle.id)).single.id,
        expense.id,
      );
      final home = await services.homeRepository.getVehicleDashboard(
        vehicle.id,
        now: DateTime(2026, 9, 20),
      );
      expect(home.monthSpendMinor, 1500);
      expect(home.spendingTrend.last.amountMinor, 1500);
      final unpriced = await services.vehicleService.addVehicle(draft());
      final empty = await services.insights.loadInsights(
        vehicleId: unpriced.id,
        range: AnalyticsDateRange.all,
      );
      expect(empty.acquisitionCount, 0);
      expect(empty.ownershipSpendMinor, 0);
    },
  );

  test('editing and removing canonical purchase price leaves expenses and IDs intact', () async {
    final services = createTestServices();
    final vehicle = await services.vehicleService.addVehicle(
      draft(price: 3000),
    );
    final expense = await services.expenseService.createExpense(
      ExpenseDraft(
        vehicleId: vehicle.id,
        categoryId: 'cat_expense_parking',
        eventDateTime: DateTime.now(),
        amountMinor: 1234,
      ),
    );
    for (final price in <double?>[2500.99, null]) {
      final updated = await services.vehicleService.updateVehicle(
        vehicle.id,
        draft(price: price),
      );
      expect(updated.id, vehicle.id);
      final result = await services.insights.loadInsights(
        vehicleId: vehicle.id,
        range: AnalyticsDateRange.all,
      );
      expect(result.acquisitionCostMinor, price == null ? 0 : 250099);
      expect(result.acquisitionCount, price == null ? 0 : 1);
      expect(result.totalSpendMinor, 1234);
      expect(
        (await services.expenses.listForVehicle(vehicle.id)).single.id,
        expense.id,
      );
    }
  });

  test(
    'purchase dates respect boundaries; undated prices count only in All time',
    () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(
        draft(price: 100, date: DateTime(2026, 9, 1)),
      );
      final undated = await services.vehicleService.addVehicle(
        draft(price: 200),
      );
      final other = await services.vehicleService.addVehicle(
        draft(price: 300, date: DateTime(2026, 10, 1)),
      );
      final september = await services.insights.loadInsights(
        vehicleId: null,
        range: AnalyticsDateRange.month,
        now: DateTime(2026, 9, 20),
      );
      expect(september.acquisitionCostMinor, 10000);
      expect(september.undatedAcquisitionCount, 1);
      final all = await services.insights.loadInsights(
        vehicleId: null,
        range: AnalyticsDateRange.all,
      );
      expect(all.acquisitionCostMinor, 60000);
      expect(all.hasAnyData, isTrue);
      for (final entry in [
        (vehicle, 10000),
        (undated, 20000),
        (other, 30000),
      ]) {
        final single = await services.insights.loadInsights(
          vehicleId: entry.$1.id,
          range: AnalyticsDateRange.all,
        );
        expect(single.acquisitionCostMinor, entry.$2);
      }
      await services.vehicleService.updateVehicle(
        vehicle.id,
        draft(price: 100, date: DateTime(2026, 10, 1)),
      );
      final moved = await services.insights.loadInsights(
        vehicleId: vehicle.id,
        range: AnalyticsDateRange.custom(
          start: DateTime(2026, 9, 1),
          endInclusive: DateTime(2026, 9, 30),
        ),
      );
      expect(moved.acquisitionCostMinor, 0);
    },
  );

  test('zero acquisition is recorded, and legacy fractional GBP rounds to minor units', () async {
    final services = createTestServices();
    for (final pair in [(0.0, 0), (1.005, 101), (1234.56, 123456)]) {
      final vehicle = await services.vehicleService.addVehicle(
        draft(price: pair.$1),
      );
      expect(vehicle.acquisitionCostMinor, pair.$2);
      expect(
        (await services.vehicles.getById(vehicle.id))!.acquisitionCostMinor,
        pair.$2,
      );
    }
  });

  test(
    'UK MPG fuel rate uses Imperial gallon and is independent of trip rounding',
    () {
      TripCostResult estimate(double distance) => FuelCalculator.tripCost(
        TripCostInput(
          distance: distance,
          distanceUnit: DistanceUnit.miles,
          fuelEconomy: 40,
          fuelEconomyUnit: FuelEconomyUnit.ukMpg,
          fuelPriceMicrosPerLitre: 1450000,
        ),
      )!;
      final expected = 145 * 4.54609 / 40;
      expect(estimate(100).costMinorPerDistance, closeTo(expected, 1e-10));
      expect(estimate(0.01).costMinorPerDistance, closeTo(expected, 1e-10));
      expect(
        DTFormatters.costPerDistance(
          estimate(100).costMinorPerDistance,
          DistanceUnit.miles,
        ),
        '£0.16/mi',
      );
    },
  );

  test('kilometre rate shares conversions and recorded Insights rate interpretation', () async {
    final services = createTestServices();
    final vehicle = await services.vehicleService.addVehicle(
      draft(unit: DistanceUnit.kilometers),
    );
    final result = FuelCalculator.tripCost(
      const TripCostInput(
        distance: 100,
        distanceUnit: DistanceUnit.kilometers,
        fuelEconomy: 8,
        fuelEconomyUnit: FuelEconomyUnit.litresPer100Km,
        fuelPriceMicrosPerLitre: 1500000,
      ),
    )!;
    expect(result.estimatedCostMinor, 1200);
    expect(result.costMinorPerDistance, 12);
    expect(
      DTFormatters.costPerDistance(
        result.costMinorPerDistance,
        DistanceUnit.kilometers,
      ),
      '£0.12/km',
    );
    final insights = await services.insights.loadInsights(
      vehicleId: vehicle.id,
      range: AnalyticsDateRange.all,
    );
    expect(insights.fuelCostMinorPerDistance, isNull);
    await services.refuelService.createRefuel(
      RefuelDraft(
        vehicleId: vehicle.id,
        eventDateTime: DateTime.now().add(const Duration(days: 1)),
        odometer: 1100,
        fuelType: FuelType.petrol,
        totalCostMinor: 1200,
        volumeMillilitres: 8000,
        unitPriceMicrosPerLitre: 1500000,
        isFullTank: true,
        missedPreviousRefuel: false,
      ),
    );
    final recorded = await services.insights.loadInsights(
      vehicleId: vehicle.id,
      range: AnalyticsDateRange.all,
    );
    expect(recorded.fuelCostMinorPerDistance, result.costMinorPerDistance);
    expect(
      DTFormatters.costPerDistance(
        recorded.fuelCostMinorPerDistance,
        recorded.scope.distanceUnit,
      ),
      DTFormatters.costPerDistance(
        result.costMinorPerDistance,
        DistanceUnit.kilometers,
      ),
    );
    expect(
      CostPerDistance.calculate(
        costMinor: result.estimatedCostMinor,
        distance: 100,
      ),
      result.costMinorPerDistance,
    );
  });

  test('invalid cost or distance produces no rate and rounding is shared', () {
    for (final distance in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        CostPerDistance.calculate(costMinor: 100, distance: distance),
        isNull,
      );
    }
    expect(CostPerDistance.calculate(costMinor: -1, distance: 1), isNull);
    expect(
      CostPerDistance.calculate(costMinor: double.infinity, distance: 1),
      isNull,
    );
    expect(
      DTFormatters.costPerDistance(null, DistanceUnit.miles),
      'Unavailable',
    );
    expect(
      DTFormatters.costPerDistance(double.nan, DistanceUnit.miles),
      'Unavailable',
    );
    expect(DTFormatters.costPerDistance(16.5, DistanceUnit.miles), '£0.17/mi');
    expect(CostPerDistance.calculate(costMinor: 0, distance: 10), 0);
    expect(
      FuelCalculator.tripCost(
        const TripCostInput(
          distance: 0,
          distanceUnit: DistanceUnit.miles,
          fuelEconomy: 40,
          fuelEconomyUnit: FuelEconomyUnit.ukMpg,
          fuelPriceMicrosPerLitre: 1450000,
        ),
      ),
      isNull,
    );
  });
}
