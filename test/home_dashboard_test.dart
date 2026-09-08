import 'package:drivetracker/features/daily_records/domain/daily_activity.dart';
import 'package:drivetracker/features/daily_records/domain/expense.dart';
import 'package:drivetracker/features/daily_records/domain/income.dart';
import 'package:drivetracker/features/daily_records/domain/record_category.dart';
import 'package:drivetracker/features/daily_records/domain/refuel.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_item.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_reminder.dart';
import 'package:drivetracker/features/maintenance/domain/service_record.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_services.dart';

void main() {
  group('Home dashboard repository', () {
    test(
      'aggregates selected vehicle spend, fuel, activity and attention',
      () async {
        final services = createTestServices();
        final now = DateTime.utc(2026, 9, 20, 12);
        final expenseCategory = await _firstCategory(
          services,
          RecordCategoryType.expense,
        );
        final incomeCategory = await _firstCategory(
          services,
          RecordCategoryType.income,
        );
        final vehicle = await services.vehicleService.addVehicle(
          _vehicleDraft('Commuter', 64000),
        );
        final otherVehicle = await services.vehicleService.addVehicle(
          _vehicleDraft('Weekend', 1000),
        );

        await services.refuelService.createRefuel(
          _refuelDraft(
            vehicle.id,
            eventDateTime: DateTime.utc(2026, 8, 10, 8),
            odometer: 64100,
            totalCostMinor: 5000,
            unitPriceMicrosPerLitre: 1250000,
          ),
        );
        await services.refuelService.createRefuel(
          _refuelDraft(
            vehicle.id,
            eventDateTime: DateTime.utc(2026, 9, 10, 8),
            odometer: 64500,
            totalCostMinor: 6000,
            unitPriceMicrosPerLitre: 1500000,
          ),
        );
        await services.expenseService.createExpense(
          ExpenseDraft(
            vehicleId: vehicle.id,
            categoryId: expenseCategory.id,
            eventDateTime: DateTime.utc(2026, 9, 11, 8),
            amountMinor: 2000,
            merchant: 'Tyre Shop',
          ),
        );
        await services.incomeService.createIncome(
          IncomeDraft(
            vehicleId: vehicle.id,
            categoryId: incomeCategory.id,
            eventDateTime: DateTime.utc(2026, 9, 12, 8),
            amountMinor: 9999,
            source: 'Mileage reclaim',
          ),
        );
        await services.serviceRecordService.createServiceRecord(
          ServiceRecordDraft(
            vehicleId: vehicle.id,
            eventDateTime: DateTime.utc(2026, 9, 13, 8),
            odometer: 64600,
            totalCostMinor: 9000,
            garage: 'ABC Garage',
            items: const [
              ServiceItemDraft(
                itemName: 'Inspection',
                allocatedCostMinor: 3000,
              ),
              ServiceItemDraft(itemName: 'Labour', allocatedCostMinor: 6000),
            ],
          ),
        );
        final oil = await services.maintenanceItemService.createMaintenanceItem(
          MaintenanceItemDraft(
            vehicleId: vehicle.id,
            name: 'Engine Oil',
            mileageInterval: 8000,
          ),
        );
        await services.serviceRecordService.createBaselineCompletion(
          item: oil,
          eventDateTime: DateTime.utc(2026, 5, 1, 8),
          odometer: 56600,
        );
        await services.refuelService.createRefuel(
          _refuelDraft(
            otherVehicle.id,
            eventDateTime: DateTime.utc(2026, 9, 15, 8),
            odometer: 1200,
            totalCostMinor: 20000,
            unitPriceMicrosPerLitre: 5000000,
          ),
        );
        await services.expenseService.createExpense(
          ExpenseDraft(
            vehicleId: otherVehicle.id,
            categoryId: expenseCategory.id,
            eventDateTime: DateTime.utc(2026, 9, 16, 8),
            amountMinor: 30000,
          ),
        );

        final dashboard = await services.homeRepository.getVehicleDashboard(
          vehicle.id,
          now: now,
        );

        expect(dashboard.vehicle.id, vehicle.id);
        expect(dashboard.currentOdometer, 64600);
        expect(dashboard.monthSpendMinor, 17000);
        expect(dashboard.latestFuelPriceMicrosPerLitre, 1500000);

        final latestEconomy = dashboard.latestFuelEconomyInterval;
        expect(latestEconomy, isNotNull);
        if (latestEconomy == null) {
          fail('Expected latest full-to-full fuel economy.');
        }
        expect(latestEconomy.ukMpg, closeTo(45.5, 0.05));

        final attention = dashboard.nextMaintenanceAttention;
        expect(attention, isNotNull);
        if (attention == null) {
          fail('Expected due maintenance attention.');
        }
        expect(attention.item.name, 'Engine Oil');
        expect(attention.state, MaintenanceReminderState.due);
        expect(attention.primaryBasis, MaintenanceReminderBasis.mileage);

        expect(dashboard.recentActivity, hasLength(5));
        expect(
          dashboard.recentActivity.map((activity) => activity.type),
          orderedEquals([
            DailyActivityType.service,
            DailyActivityType.income,
            DailyActivityType.expense,
            DailyActivityType.refuel,
            DailyActivityType.refuel,
          ]),
        );
        expect(
          dashboard.recentActivity.map((activity) => activity.vehicleId),
          everyElement(vehicle.id),
        );
      },
    );

    test(
      'six-month spending trend uses event dates and selected vehicle',
      () async {
        final services = createTestServices();
        final now = DateTime.utc(2026, 3, 15, 12);
        final expenseCategory = await _firstCategory(
          services,
          RecordCategoryType.expense,
        );
        final incomeCategory = await _firstCategory(
          services,
          RecordCategoryType.income,
        );
        final vehicle = await services.vehicleService.addVehicle(
          _vehicleDraft('Commuter', 1000),
        );
        final otherVehicle = await services.vehicleService.addVehicle(
          _vehicleDraft('Weekend', 1000),
        );

        await services.refuelService.createRefuel(
          _refuelDraft(
            vehicle.id,
            eventDateTime: DateTime.utc(2025, 9, 15, 8),
            odometer: 1050,
          ),
        );
        await services.refuelService.createRefuel(
          _refuelDraft(
            vehicle.id,
            eventDateTime: DateTime.utc(2025, 12, 15, 8),
            odometer: 1100,
            totalCostMinor: 5000,
          ),
        );
        await services.expenseService.createExpense(
          ExpenseDraft(
            vehicleId: vehicle.id,
            categoryId: expenseCategory.id,
            eventDateTime: DateTime.utc(2026, 1, 15, 8),
            amountMinor: 2000,
          ),
        );
        await services.serviceRecordService.createServiceRecord(
          ServiceRecordDraft(
            vehicleId: vehicle.id,
            eventDateTime: DateTime.utc(2026, 2, 15, 8),
            odometer: 1200,
            totalCostMinor: 9000,
            items: const [
              ServiceItemDraft(
                itemName: 'Inspection',
                allocatedCostMinor: 1000,
              ),
              ServiceItemDraft(itemName: 'Labour', allocatedCostMinor: 8000),
            ],
          ),
        );
        await services.incomeService.createIncome(
          IncomeDraft(
            vehicleId: vehicle.id,
            categoryId: incomeCategory.id,
            eventDateTime: DateTime.utc(2026, 2, 20, 8),
            amountMinor: 9999,
          ),
        );
        await services.refuelService.createRefuel(
          _refuelDraft(
            vehicle.id,
            eventDateTime: DateTime.utc(2026, 3, 1, 8),
            odometer: 1300,
            totalCostMinor: 3000,
            volumeMillilitres: 24000,
          ),
        );
        await services.refuelService.createRefuel(
          _refuelDraft(
            otherVehicle.id,
            eventDateTime: DateTime.utc(2026, 1, 15, 8),
            odometer: 1100,
          ),
        );

        final trend = await services.financialSummary.spendingTrendForVehicle(
          vehicle.id,
          now: now,
        );

        expect(
          trend.map((bucket) => '${bucket.month.year}-${bucket.month.month}'),
          orderedEquals([
            '2025-10',
            '2025-11',
            '2025-12',
            '2026-1',
            '2026-2',
            '2026-3',
          ]),
        );
        expect(
          trend.map((bucket) => bucket.amountMinor),
          orderedEquals([0, 0, 5000, 2000, 9000, 3000]),
        );
        expect(
          await services.financialSummary.spendingTrendForVehicle(
            vehicle.id,
            now: now,
            monthCount: 0,
          ),
          isEmpty,
        );
      },
    );

    test('normal and archived maintenance do not surface on Home', () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(
        _vehicleDraft('Commuter', 70000),
      );
      final normal = await services.maintenanceItemService
          .createMaintenanceItem(
            MaintenanceItemDraft(
              vehicleId: vehicle.id,
              name: 'Air Filter',
              mileageInterval: 8000,
            ),
          );
      await services.serviceRecordService.createBaselineCompletion(
        item: normal,
        eventDateTime: DateTime.utc(2026, 1, 1, 8),
        odometer: 65000,
      );
      final archived = await services.maintenanceItemService
          .createMaintenanceItem(
            MaintenanceItemDraft(
              vehicleId: vehicle.id,
              name: 'Archived Tyres',
              mileageInterval: 1000,
            ),
          );
      await services.serviceRecordService.createBaselineCompletion(
        item: archived,
        eventDateTime: DateTime.utc(2026, 1, 2, 8),
        odometer: 50000,
      );
      await services.maintenanceItemService.archiveMaintenanceItem(archived.id);

      final dashboard = await services.homeRepository.getVehicleDashboard(
        vehicle.id,
        now: DateTime.utc(2026, 9, 20, 12),
      );

      expect(dashboard.nextMaintenanceAttention, isNull);
    });
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
}) {
  return RefuelDraft(
    vehicleId: vehicleId,
    eventDateTime: eventDateTime,
    odometer: odometer,
    fuelType: FuelType.petrol,
    totalCostMinor: totalCostMinor,
    volumeMillilitres: volumeMillilitres,
    unitPriceMicrosPerLitre: unitPriceMicrosPerLitre,
    isFullTank: true,
    missedPreviousRefuel: false,
  );
}

Future<RecordCategory> _firstCategory(
  TestServices services,
  RecordCategoryType type,
) async {
  return (await services.categories.listByType(type)).first;
}
