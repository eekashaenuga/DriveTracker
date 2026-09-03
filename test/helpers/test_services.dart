import 'dart:io';
import 'dart:math';

import 'package:drivetracker/core/database/app_database.dart';
import 'package:drivetracker/core/utilities/id_generator.dart';
import 'package:drivetracker/features/odometer/data/odometer_repository.dart';
import 'package:drivetracker/features/odometer/domain/odometer_service.dart';
import 'package:drivetracker/features/settings/data/settings_repository.dart';
import 'package:drivetracker/features/vehicles/data/vehicle_repository.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TestServices {
  TestServices(this.database)
    : vehicles = VehicleRepository(database),
      odometers = OdometerRepository(database),
      settings = SettingsRepository(database) {
    final idGenerator = IdGenerator(random: Random(42));
    vehicleService = VehicleService(
      database: database,
      vehicleRepository: vehicles,
      odometerRepository: odometers,
      settingsRepository: settings,
      idGenerator: idGenerator,
      clock: () => DateTime.utc(2026, 1, 1, 12),
    );
    odometerService = OdometerService(
      vehicleRepository: vehicles,
      odometerRepository: odometers,
      idGenerator: idGenerator,
      clock: () => DateTime.utc(2026, 1, 2, 12),
    );
  }

  final AppDatabase database;
  final VehicleRepository vehicles;
  final OdometerRepository odometers;
  final SettingsRepository settings;
  late final VehicleService vehicleService;
  late final OdometerService odometerService;
}

TestServices createTestServices() {
  sqfliteFfiInit();
  final dir = Directory.systemTemp.createTempSync('drivetracker_test_');
  final database = AppDatabase(
    databaseFactory: databaseFactoryFfi,
    databasePath: p.join(dir.path, 'drive_tracker.db'),
  );
  addTearDown(() async {
    await database.close();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  return TestServices(database);
}

Future<TestServices> createFileBackedTestServices() async {
  sqfliteFfiInit();
  final dir = await Directory.systemTemp.createTemp('drivetracker_test_');

  final database = AppDatabase(
    databaseFactory: databaseFactoryFfi,
    databasePath: p.join(dir.path, 'drive_tracker.db'),
  );
  addTearDown(() async {
    await database.close();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  return TestServices(database);
}
