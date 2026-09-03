import 'package:drivetracker/core/database/app_database.dart';
import 'package:drivetracker/core/utilities/validation_exception.dart';
import 'package:drivetracker/features/odometer/data/odometer_repository.dart';
import 'package:drivetracker/features/odometer/domain/odometer_policy.dart';
import 'package:drivetracker/features/odometer/domain/odometer_service.dart';
import 'package:drivetracker/features/settings/data/settings_repository.dart';
import 'package:drivetracker/features/vehicles/data/vehicle_repository.dart';
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
}) {
  return VehicleDraft(
    name: name,
    make: 'Ford',
    model: 'Focus',
    currentOdometer: odometer,
    fuelType: FuelType.petrol,
    distanceUnit: unit,
  );
}
