import 'package:drivetracker/core/database/app_database.dart';
import 'package:drivetracker/core/utilities/validation_exception.dart';
import 'package:drivetracker/features/daily_records/domain/expense.dart';
import 'package:drivetracker/features/daily_records/domain/income.dart';
import 'package:drivetracker/features/daily_records/domain/record_category.dart';
import 'package:drivetracker/features/daily_records/domain/refuel.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_item.dart';
import 'package:drivetracker/features/maintenance/domain/service_record.dart';
import 'package:drivetracker/features/odometer/data/odometer_repository.dart';
import 'package:drivetracker/features/odometer/domain/odometer_policy.dart';
import 'package:drivetracker/features/odometer/domain/odometer_service.dart';
import 'package:drivetracker/features/settings/data/settings_repository.dart';
import 'package:drivetracker/features/vehicles/data/vehicle_repository.dart';
import 'package:drivetracker/features/vehicles/domain/distance_unit_conversion.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_validator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_services.dart';

void main() {
  test('vehicle creation validation rejects missing required fields', () {
    final errors = VehicleValidator.validate(
      const VehicleDraft(
        name: '',
        make: ' ',
        model: '',
        currentOdometer: -1,
        fuelType: FuelType.petrol,
        distanceUnit: DistanceUnit.miles,
      ),
      requireInitialOdometer: true,
    );

    expect(errors, contains('Vehicle name is required.'));
    expect(errors, contains('Make is required.'));
    expect(errors, contains('Model is required.'));
    expect(errors, contains('Current odometer cannot be negative.'));
  });

  test('odometer progression accepts normal increases', () {
    const policy = OdometerPolicy();

    final assessment = policy.assess(
      currentOdometer: 64000,
      newOdometer: 64200,
    );

    expect(assessment.decision, OdometerDecision.accepted);
    expect(assessment.difference, 200);
  });

  test('odometer progression warns for unusually high increases', () {
    const policy = OdometerPolicy();

    final assessment = policy.assess(
      currentOdometer: 70902,
      newOdometer: 79002,
    );

    expect(assessment.decision, OdometerDecision.unusuallyLargeIncrease);
    expect(assessment.needsConfirmation, isTrue);
    expect(assessment.difference, 8100);
  });

  test('current odometer is the highest valid reading', () async {
    final services = createTestServices();

    final vehicle = await services.vehicleService.addVehicle(_draft(64000));
    await services.odometerService.recordManualReading(
      vehicleId: vehicle.id,
      odometer: 64200,
    );
    await services.odometerService.recordManualReading(
      vehicleId: vehicle.id,
      odometer: 64500,
    );

    final current = await services.odometers.currentOdometerForVehicle(
      vehicle.id,
    );

    expect(current, 64500);
  });

  test('historical lower reading does not reduce current odometer', () async {
    final services = createTestServices();

    final vehicle = await services.vehicleService.addVehicle(_draft(64000));
    await services.odometerService.recordManualReading(
      vehicleId: vehicle.id,
      odometer: 64500,
    );
    await services.odometerService.recordManualReading(
      vehicleId: vehicle.id,
      odometer: 63900,
      allowHistorical: true,
    );

    final current = await services.odometers.currentOdometerForVehicle(
      vehicle.id,
    );

    expect(current, 64500);
  });

  test('unusually high reading requires confirmation before saving', () async {
    final services = createTestServices();

    final vehicle = await services.vehicleService.addVehicle(_draft(70902));

    expect(
      () => services.odometerService.recordManualReading(
        vehicleId: vehicle.id,
        odometer: 79002,
      ),
      throwsA(isA<OdometerConfirmationRequired>()),
    );

    await services.odometerService.recordManualReading(
      vehicleId: vehicle.id,
      odometer: 79002,
      confirmLargeIncrease: true,
    );

    expect(
      await services.odometers.currentOdometerForVehicle(vehicle.id),
      79002,
    );
  });

  test('invalid negative odometer readings are rejected', () async {
    final services = createTestServices();

    final vehicle = await services.vehicleService.addVehicle(_draft(1000));

    expect(
      () => services.odometerService.recordManualReading(
        vehicleId: vehicle.id,
        odometer: -1,
      ),
      throwsA(isA<ValidationException>()),
    );
  });

  test('multiple vehicles maintain independent odometer histories', () async {
    final services = createTestServices();

    final commuter = await services.vehicleService.addVehicle(
      _draft(1000, name: 'Commuter'),
    );
    final weekend = await services.vehicleService.addVehicle(
      _draft(25000, name: 'Weekend'),
    );

    await services.odometerService.recordManualReading(
      vehicleId: commuter.id,
      odometer: 1200,
    );

    expect(
      await services.odometers.currentOdometerForVehicle(commuter.id),
      1200,
    );
    expect(
      await services.odometers.currentOdometerForVehicle(weekend.id),
      25000,
    );
  });

  test(
    'vehicle archiving preserves data and removes active selection',
    () async {
      final services = createTestServices();

      final commuter = await services.vehicleService.addVehicle(
        _draft(1000, name: 'Commuter'),
      );
      final weekend = await services.vehicleService.addVehicle(
        _draft(25000, name: 'Weekend'),
      );

      expect(await services.settings.getSelectedVehicleId(), weekend.id);

      await services.vehicleService.archiveVehicle(weekend.id);

      final active = await services.vehicles.listActive();
      final archived = await services.vehicles.listArchived();

      expect(active.map((vehicle) => vehicle.id), [commuter.id]);
      expect(archived.map((vehicle) => vehicle.id), [weekend.id]);
      expect(await services.settings.getSelectedVehicleId(), commuter.id);
      expect(
        await services.odometers.currentOdometerForVehicle(weekend.id),
        25000,
      );
      expect(
        () => services.odometerService.recordManualReading(
          vehicleId: weekend.id,
          odometer: 25100,
        ),
        throwsA(isA<ValidationException>()),
      );
    },
  );

  test(
    'selected vehicle falls back to null after archiving last active vehicle',
    () async {
      final services = createTestServices();

      final vehicle = await services.vehicleService.addVehicle(_draft(1000));

      await services.vehicleService.archiveVehicle(vehicle.id);

      expect(await services.vehicles.listActive(), isEmpty);
      expect(await services.settings.getSelectedVehicleId(), isNull);
    },
  );

  test('restoring archived vehicle reactivates same row and preserves odometer history', () async {
    final services = createTestServices();

    final vehicle = await services.vehicleService.addVehicle(_draft(1000));
    final entry = await services.odometerService.recordManualReading(
      vehicleId: vehicle.id,
      odometer: 1200,
    );

    await services.vehicleService.archiveVehicle(vehicle.id);
    await services.vehicleService.restoreVehicle(vehicle.id);

    final active = await services.vehicles.listActive();
    final archived = await services.vehicles.listArchived();
    final entries = await services.odometers.allForVehicle(vehicle.id);

    expect(active.map((vehicle) => vehicle.id), [vehicle.id]);
    expect(archived, isEmpty);
    expect(await services.settings.getSelectedVehicleId(), vehicle.id);
    expect(
      await services.odometers.currentOdometerForVehicle(vehicle.id),
      1200,
    );
    expect(entries.map((entry) => entry.id), contains(entry.id));
  });

  test(
    'manual odometer edits preserve entry id and current mileage rules',
    () async {
      final services = createTestServices();

      final vehicle = await services.vehicleService.addVehicle(_draft(64000));
      final historical = await services.odometerService.recordManualReading(
        vehicleId: vehicle.id,
        odometer: 64500,
        eventDateTime: DateTime.utc(2026, 1, 2, 8),
      );
      await services.odometerService.recordManualReading(
        vehicleId: vehicle.id,
        odometer: 65000,
        eventDateTime: DateTime.utc(2026, 1, 3, 8),
      );

      final updated = await services.odometerService.updateManualReading(
        entryId: historical.id,
        odometer: 64600,
        eventDateTime: historical.eventDateTime,
      );

      expect(updated.id, historical.id);
      expect(updated.odometer, 64600);
      expect(
        await services.odometers.currentOdometerForVehicle(vehicle.id),
        65000,
      );
      expect(
        (await services.odometers.getById(historical.id))?.odometer,
        64600,
      );
    },
  );

  test('manual odometer edit rejects negative readings', () async {
    final services = createTestServices();

    final vehicle = await services.vehicleService.addVehicle(_draft(1000));
    final entry = await services.odometerService.recordManualReading(
      vehicleId: vehicle.id,
      odometer: 1200,
    );

    expect(
      () => services.odometerService.updateManualReading(
        entryId: entry.id,
        odometer: -1,
        eventDateTime: entry.eventDateTime,
      ),
      throwsA(isA<ValidationException>()),
    );
  });

  test(
    'manual odometer edit requires confirmation for unusual sequence',
    () async {
      final services = createTestServices();

      final vehicle = await services.vehicleService.addVehicle(_draft(1000));
      final middle = await services.odometerService.recordManualReading(
        vehicleId: vehicle.id,
        odometer: 1500,
        eventDateTime: DateTime.utc(2026, 1, 2, 8),
      );
      await services.odometerService.recordManualReading(
        vehicleId: vehicle.id,
        odometer: 2000,
        eventDateTime: DateTime.utc(2026, 1, 3, 8),
      );

      expect(
        () => services.odometerService.updateManualReading(
          entryId: middle.id,
          odometer: 2500,
          eventDateTime: middle.eventDateTime,
        ),
        throwsA(isA<OdometerEditConfirmationRequired>()),
      );

      final updated = await services.odometerService.updateManualReading(
        entryId: middle.id,
        odometer: 2500,
        eventDateTime: middle.eventDateTime,
        confirmUnusualSequence: true,
      );

      expect(updated.id, middle.id);
      expect(
        await services.odometers.currentOdometerForVehicle(vehicle.id),
        2500,
      );
    },
  );

  test(
    'vehicle unit changes convert distance data and keep vehicles independent',
    () async {
      final services = await createFileBackedTestServices();
      final path = (await services.database.database).path;

      final commuter = await services.vehicleService.addVehicle(
        _draft(10000, purchaseMileage: 9000),
      );
      final weekend = await services.vehicleService.addVehicle(
        _draft(5000, name: 'Weekend'),
      );
      final expenseCategory = await _firstCategory(
        services,
        RecordCategoryType.expense,
      );
      final incomeCategory = await _firstCategory(
        services,
        RecordCategoryType.income,
      );
      final oil = await services.maintenanceItemService.createMaintenanceItem(
        MaintenanceItemDraft(
          vehicleId: commuter.id,
          name: 'Oil',
          mileageInterval: 5000,
          mileageWarning: 1000,
        ),
      );
      final refuel = await services.refuelService.createRefuel(
        RefuelDraft(
          vehicleId: commuter.id,
          eventDateTime: DateTime.utc(2026, 1, 3, 9),
          odometer: 10100,
          fuelType: FuelType.petrol,
          totalCostMinor: 5000,
          volumeMillilitres: 40000,
          unitPriceMicrosPerLitre: 1250000,
          isFullTank: true,
          missedPreviousRefuel: false,
        ),
      );
      final expense = await services.expenseService.createExpense(
        ExpenseDraft(
          vehicleId: commuter.id,
          categoryId: expenseCategory.id,
          eventDateTime: DateTime.utc(2026, 1, 4, 9),
          odometer: 10200,
          amountMinor: 1200,
        ),
      );
      final income = await services.incomeService.createIncome(
        IncomeDraft(
          vehicleId: commuter.id,
          categoryId: incomeCategory.id,
          eventDateTime: DateTime.utc(2026, 1, 5, 9),
          odometer: 10300,
          amountMinor: 4500,
        ),
      );
      final service = await services.serviceRecordService.createServiceRecord(
        ServiceRecordDraft(
          vehicleId: commuter.id,
          eventDateTime: DateTime.utc(2026, 1, 6, 9),
          odometer: 10400,
          totalCostMinor: 9000,
          items: [
            ServiceItemDraft(maintenanceItemId: oil.id, itemName: oil.name),
          ],
        ),
      );

      final updated = await services.vehicleService.updateVehicleDistanceUnit(
        commuter.id,
        DistanceUnit.kilometers,
      );

      expect(updated.distanceUnit, DistanceUnit.kilometers);
      expect(updated.purchaseMileage, _toKm(9000));
      expect(
        await services.odometers.currentOdometerForVehicle(commuter.id),
        _toKm(10400),
      );
      expect(
        (await services.refuels.getById(refuel.id))?.odometer,
        _toKm(10100),
      );
      expect(
        (await services.expenses.getById(expense.id))?.odometer,
        _toKm(10200),
      );
      expect(
        (await services.incomes.getById(income.id))?.odometer,
        _toKm(10300),
      );
      expect(
        (await services.serviceRecords.getById(service.record.id))?.odometer,
        _toKm(10400),
      );
      final convertedOil = await services.maintenanceItems.getById(oil.id);
      expect(convertedOil?.mileageInterval, _toKm(5000));
      expect(convertedOil?.mileageWarning, _toKm(1000));
      expect(
        (await services.vehicles.getById(weekend.id))?.distanceUnit,
        DistanceUnit.miles,
      );
      expect(
        await services.odometers.currentOdometerForVehicle(weekend.id),
        5000,
      );

      await services.database.close();

      final reopened = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: path,
      );
      addTearDown(reopened.close);
      final vehicles = VehicleRepository(reopened);
      final odometers = OdometerRepository(reopened);

      expect(
        (await vehicles.getById(commuter.id))?.distanceUnit,
        DistanceUnit.kilometers,
      );
      expect(
        await odometers.currentOdometerForVehicle(commuter.id),
        _toKm(10400),
      );
    },
  );

  test(
    'database-backed repositories persist vehicle and odometer data',
    () async {
      final services = await createFileBackedTestServices();
      final path = (await services.database.database).path;

      final vehicle = await services.vehicleService.addVehicle(_draft(5000));
      await services.database.close();

      final reopened = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: path,
      );
      addTearDown(reopened.close);
      final vehicles = VehicleRepository(reopened);
      final odometers = OdometerRepository(reopened);
      final settings = SettingsRepository(reopened);
      final odometerService = OdometerService(
        vehicleRepository: vehicles,
        odometerRepository: odometers,
      );

      expect((await vehicles.listActive()).single.id, vehicle.id);
      expect(await settings.getSelectedVehicleId(), vehicle.id);
      expect(await odometers.currentOdometerForVehicle(vehicle.id), 5000);
      await odometerService.recordManualReading(
        vehicleId: vehicle.id,
        odometer: 5050,
      );
      expect(await odometers.currentOdometerForVehicle(vehicle.id), 5050);
    },
  );
}

VehicleDraft _draft(
  int odometer, {
  String name = 'Commuter',
  DistanceUnit unit = DistanceUnit.miles,
  int? purchaseMileage,
}) {
  return VehicleDraft(
    name: name,
    make: 'Ford',
    model: 'Focus',
    currentOdometer: odometer,
    fuelType: FuelType.petrol,
    distanceUnit: unit,
    purchaseMileage: purchaseMileage,
  );
}

Future<RecordCategory> _firstCategory(
  TestServices services,
  RecordCategoryType type,
) async {
  return (await services.categories.listByType(type)).first;
}

int _toKm(int miles) {
  return DistanceUnitConversion.convertWholeDistance(
    miles,
    from: DistanceUnit.miles,
    to: DistanceUnit.kilometers,
  );
}
