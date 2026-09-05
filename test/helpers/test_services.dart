import 'dart:io';
import 'dart:math';

import 'package:drivetracker/core/database/app_database.dart';
import 'package:drivetracker/core/utilities/id_generator.dart';
import 'package:drivetracker/features/daily_records/data/activity_repository.dart';
import 'package:drivetracker/features/daily_records/data/category_repository.dart';
import 'package:drivetracker/features/daily_records/data/expense_repository.dart';
import 'package:drivetracker/features/daily_records/data/financial_summary_repository.dart';
import 'package:drivetracker/features/daily_records/data/income_repository.dart';
import 'package:drivetracker/features/daily_records/data/refuel_repository.dart';
import 'package:drivetracker/features/daily_records/domain/category_service.dart';
import 'package:drivetracker/features/daily_records/domain/expense_service.dart';
import 'package:drivetracker/features/daily_records/domain/income_service.dart';
import 'package:drivetracker/features/daily_records/domain/refuel_service.dart';
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
      settings = SettingsRepository(database),
      categories = CategoryRepository(database),
      refuels = RefuelRepository(database),
      expenses = ExpenseRepository(database),
      incomes = IncomeRepository(database),
      activities = ActivityRepository(database) {
    final idGenerator = IdGenerator(random: Random(42));
    var clockTick = 0;
    DateTime testClock(int day, int hour) {
      final value = DateTime.utc(
        2026,
        1,
        day,
        hour,
      ).add(Duration(minutes: clockTick));
      clockTick += 1;
      return value;
    }

    vehicleService = VehicleService(
      database: database,
      vehicleRepository: vehicles,
      odometerRepository: odometers,
      settingsRepository: settings,
      idGenerator: idGenerator,
      clock: () => testClock(1, 12),
    );
    odometerService = OdometerService(
      vehicleRepository: vehicles,
      odometerRepository: odometers,
      idGenerator: idGenerator,
      clock: () => testClock(2, 12),
    );
    categoryService = CategoryService(
      categoryRepository: categories,
      idGenerator: idGenerator,
      clock: () => testClock(2, 13),
    );
    refuelService = RefuelService(
      database: database,
      vehicleRepository: vehicles,
      odometerRepository: odometers,
      refuelRepository: refuels,
      idGenerator: idGenerator,
      clock: () => testClock(3, 12),
    );
    expenseService = ExpenseService(
      database: database,
      vehicleRepository: vehicles,
      categoryRepository: categories,
      odometerRepository: odometers,
      expenseRepository: expenses,
      idGenerator: idGenerator,
      clock: () => testClock(4, 12),
    );
    incomeService = IncomeService(
      database: database,
      vehicleRepository: vehicles,
      categoryRepository: categories,
      odometerRepository: odometers,
      incomeRepository: incomes,
      idGenerator: idGenerator,
      clock: () => testClock(5, 12),
    );
    financialSummary = FinancialSummaryRepository(
      refuelRepository: refuels,
      expenseRepository: expenses,
    );
  }

  final AppDatabase database;
  final VehicleRepository vehicles;
  final OdometerRepository odometers;
  final SettingsRepository settings;
  final CategoryRepository categories;
  final RefuelRepository refuels;
  final ExpenseRepository expenses;
  final IncomeRepository incomes;
  final ActivityRepository activities;
  late final VehicleService vehicleService;
  late final OdometerService odometerService;
  late final CategoryService categoryService;
  late final RefuelService refuelService;
  late final ExpenseService expenseService;
  late final IncomeService incomeService;
  late final FinancialSummaryRepository financialSummary;
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
