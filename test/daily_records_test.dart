import 'dart:io';

import 'package:drivetracker/core/database/app_database.dart';
import 'package:drivetracker/core/database/database_migrations.dart';
import 'package:drivetracker/core/utilities/money.dart';
import 'package:drivetracker/core/utilities/validation_exception.dart';
import 'package:drivetracker/features/daily_records/domain/daily_activity.dart';
import 'package:drivetracker/features/daily_records/domain/expense.dart';
import 'package:drivetracker/features/daily_records/domain/fuel_economy_calculator.dart';
import 'package:drivetracker/features/daily_records/domain/fuel_entry_calculator.dart';
import 'package:drivetracker/features/daily_records/domain/income.dart';
import 'package:drivetracker/features/daily_records/domain/record_category.dart';
import 'package:drivetracker/features/daily_records/domain/refuel.dart';
import 'package:drivetracker/features/maintenance/domain/service_record.dart';
import 'package:drivetracker/features/odometer/domain/odometer_entry.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_services.dart';

void main() {
  test(
    'V1 to latest migration preserves vehicles, odometer and settings',
    () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('drivetracker_v1_');
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final path = p.join(dir.path, 'drive_tracker.db');
      final oldDb = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: DatabaseMigrations.createSchema,
        ),
      );
      await oldDb.insert('vehicles', _vehicleMap('veh_1'));
      await oldDb.insert('odometer_entries', _odometerMap('odo_1', 'veh_1'));
      await oldDb.insert('app_settings', {
        'key': 'selected_vehicle_id',
        'value': 'veh_1',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
      await oldDb.close();

      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: path,
      );
      addTearDown(database.close);
      final db = await database.database;

      expect(await db.getVersion(), 3);
      expect((await db.query('vehicles')).single['id'], 'veh_1');
      expect((await db.query('odometer_entries')).single['id'], 'odo_1');
      expect((await db.query('app_settings')).single['value'], 'veh_1');
      expect(await db.query('refuels'), isEmpty);
      expect(await db.query('expenses'), isEmpty);
      expect(await db.query('income_records'), isEmpty);
      expect(await db.query('maintenance_items'), isEmpty);
      expect(await db.query('services'), isEmpty);
      expect(await db.query('service_items'), isEmpty);
      expect(
        (await db.query(
          'record_categories',
          where: 'type = ?',
          whereArgs: ['EXPENSE'],
        )).length,
        greaterThan(5),
      );
    },
  );

  group('fuel entry calculations', () {
    test('any two values calculate the third', () {
      expect(
        FuelEntryCalculator.calculateUnitPriceMicrosPerLitre(
          totalCostMinor: 5000,
          volumeMillilitres: 40000,
        ),
        1250000,
      );
      expect(
        FuelEntryCalculator.calculateTotalCostMinor(
          volumeMillilitres: 40000,
          unitPriceMicrosPerLitre: 1250000,
        ),
        5000,
      );
      expect(
        FuelEntryCalculator.calculateVolumeMillilitres(
          totalCostMinor: 5000,
          unitPriceMicrosPerLitre: 1250000,
        ),
        40000,
      );
    });

    test('invalid zero and negative values are rejected', () {
      expect(
        FuelEntryCalculator.calculateTotalCostMinor(
          volumeMillilitres: 0,
          unitPriceMicrosPerLitre: 1250000,
        ),
        isNull,
      );
      expect(
        FuelEntryCalculator.calculateVolumeMillilitres(
          totalCostMinor: -1,
          unitPriceMicrosPerLitre: 1250000,
        ),
        isNull,
      );
    });

    test('rounding and UK pence-per-litre parsing are deterministic', () {
      expect(FuelNumbers.parsePencePerLitreToMicros('139.7'), 1397000);
      expect(FuelNumbers.parsePoundsPerLitreToMicros('1.397'), 1397000);
      expect(FuelNumbers.formatPencePerLitre(1397000), '139.7 p/L');

      final state = FuelEntryCalculator.update(
        current: const FuelEntryValues(totalCostMinor: 5000),
        manualFields: const [FuelEntryField.totalCost],
        editedField: FuelEntryField.volume,
        editedValue: 33330,
      );

      expect(state.calculatedField, FuelEntryField.unitPrice);
      expect(state.values.unitPriceMicrosPerLitre, 1500150);
    });
  });

  group('refuels and odometer', () {
    test(
      'create, edit and delete synchronize one linked odometer entry',
      () async {
        final services = createTestServices();
        final vehicle = await services.vehicleService.addVehicle(_draft(64000));

        final refuel = await services.refuelService.createRefuel(
          _refuelDraft(vehicle.id, odometer: 64100),
        );
        final linked = await services.odometers.getBySource(
          OdometerSourceType.refuel,
          refuel.id,
        );

        expect(linked, isNotNull);
        expect(linked!.odometer, 64100);

        final updated = await services.refuelService.updateRefuel(
          refuel.id,
          _refuelDraft(
            vehicle.id,
            odometer: 64200,
            totalCostMinor: 6250,
            unitPriceMicrosPerLitre: 1562500,
          ),
        );
        final linkedAfterEdit = await services.odometers.getBySource(
          OdometerSourceType.refuel,
          updated.id,
        );
        final refuelLinks = (await services.odometers.allForVehicle(vehicle.id))
            .where((entry) => entry.sourceType == OdometerSourceType.refuel);

        expect(linkedAfterEdit!.id, linked.id);
        expect(linkedAfterEdit.odometer, 64200);
        expect(refuelLinks.length, 1);

        await services.refuelService.deleteRefuel(refuel.id);
        expect(
          await services.odometers.getBySource(
            OdometerSourceType.refuel,
            refuel.id,
          ),
          isNull,
        );
        expect(
          await services.odometers.currentOdometerForVehicle(vehicle.id),
          64000,
        );
      },
    );

    test('historical refuel does not rewind current odometer', () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(_draft(64000));
      await services.odometerService.recordManualReading(
        vehicleId: vehicle.id,
        odometer: 70000,
      );

      await services.refuelService.createRefuel(
        _refuelDraft(vehicle.id, odometer: 65000),
        allowHistorical: true,
      );

      expect(
        await services.odometers.currentOdometerForVehicle(vehicle.id),
        70000,
      );
    });

    test('multiple vehicles remain independent', () async {
      final services = createTestServices();
      final first = await services.vehicleService.addVehicle(
        _draft(1000, name: 'First'),
      );
      final second = await services.vehicleService.addVehicle(
        _draft(5000, name: 'Second'),
      );

      await services.refuelService.createRefuel(
        _refuelDraft(first.id, odometer: 1100),
      );

      expect(await services.refuels.listForVehicle(first.id), hasLength(1));
      expect(await services.refuels.listForVehicle(second.id), isEmpty);
      expect(
        await services.odometers.currentOdometerForVehicle(second.id),
        5000,
      );
    });
  });

  group('fuel economy', () {
    test('full-to-full intervals accumulate partial fills correctly', () {
      final intervals = FuelEconomyCalculator.validIntervals(
        distanceUnit: DistanceUnit.miles,
        refuels: [
          _refuel('start', 64500, 30000),
          _refuel('partial', 64700, 8000, full: false),
          _refuel('end', 64900, 32000),
        ],
      );

      expect(intervals, hasLength(1));
      expect(intervals.single.distance, 400);
      expect(intervals.single.volumeMillilitres, 40000);
      expect(intervals.single.ukMpg, closeTo(45.46, 0.01));
    });

    test(
      'missed refuel, insufficient data and bad mileage do not fabricate MPG',
      () {
        expect(
          FuelEconomyCalculator.validIntervals(
            distanceUnit: DistanceUnit.miles,
            refuels: [_refuel('only', 64500, 30000)],
          ),
          isEmpty,
        );
        expect(
          FuelEconomyCalculator.validIntervals(
            distanceUnit: DistanceUnit.miles,
            refuels: [
              _refuel('start', 64500, 30000),
              _refuel('missed', 64900, 32000, missed: true),
            ],
          ),
          isEmpty,
        );
        expect(
          FuelEconomyCalculator.validIntervals(
            distanceUnit: DistanceUnit.miles,
            refuels: [
              _refuel('start', 64500, 30000, eventMinute: 1),
              _refuel('bad', 64400, 32000, eventMinute: 2),
            ],
          ),
          isEmpty,
        );
      },
    );

    test('missed-history full tank resets before a later valid interval', () {
      final intervals = FuelEconomyCalculator.validIntervals(
        distanceUnit: DistanceUnit.miles,
        refuels: [
          _refuel('a', 64500, 30000, eventMinute: 1),
          _refuel('b', 64900, 32000, missed: true, eventMinute: 2),
          _refuel('c', 65200, 30000, eventMinute: 3),
        ],
      );

      expect(intervals, hasLength(1));
      expect(intervals.single.startRefuel.id, 'b');
      expect(intervals.single.endRefuel.id, 'c');
      expect(intervals.single.distance, 300);
      expect(intervals.single.volumeMillilitres, 30000);
    });
  });

  group('expenses, income and categories', () {
    test(
      'expense create/edit/delete and optional odometer linkage work',
      () async {
        final services = createTestServices();
        final vehicle = await services.vehicleService.addVehicle(_draft(1000));
        final category = await _firstCategory(
          services,
          RecordCategoryType.expense,
        );

        final expense = await services.expenseService.createExpense(
          ExpenseDraft(
            vehicleId: vehicle.id,
            categoryId: category.id,
            eventDateTime: DateTime.utc(2026, 1, 7),
            amountMinor: 1200,
            odometer: 1100,
            merchant: 'Car park',
          ),
        );
        expect(await services.expenses.getById(expense.id), isNotNull);
        expect(
          await services.odometers.getBySource(
            OdometerSourceType.expense,
            expense.id,
          ),
          isNotNull,
        );

        await services.expenseService.updateExpense(
          expense.id,
          ExpenseDraft(
            vehicleId: vehicle.id,
            categoryId: category.id,
            eventDateTime: DateTime.utc(2026, 1, 8),
            amountMinor: 1500,
            merchant: 'Car park',
          ),
        );
        expect(
          await services.odometers.getBySource(
            OdometerSourceType.expense,
            expense.id,
          ),
          isNull,
        );

        await services.expenseService.deleteExpense(expense.id);
        expect(await services.expenses.getById(expense.id), isNull);
      },
    );

    test('income create/edit/delete and custom category work', () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(_draft(1000));
      final category = await services.categoryService.createCustomCategory(
        type: RecordCategoryType.income,
        name: 'Courier bonus',
      );

      final income = await services.incomeService.createIncome(
        IncomeDraft(
          vehicleId: vehicle.id,
          categoryId: category.id,
          eventDateTime: DateTime.utc(2026, 1, 7),
          amountMinor: 4500,
          odometer: 1200,
          source: 'Delivery app',
        ),
      );

      final updated = await services.incomeService.updateIncome(
        income.id,
        IncomeDraft(
          vehicleId: vehicle.id,
          categoryId: category.id,
          eventDateTime: DateTime.utc(2026, 1, 8),
          amountMinor: 5000,
          source: 'Delivery app',
        ),
      );

      expect(updated.createdAt, income.createdAt);
      expect(updated.updatedAt.isAfter(income.updatedAt), isTrue);
      expect(await services.incomes.getById(income.id), isNotNull);

      await services.incomeService.deleteIncome(income.id);
      expect(await services.incomes.getById(income.id), isNull);
    });

    test('invalid categories and money are rejected', () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(_draft(1000));
      final expenseCategory = await _firstCategory(
        services,
        RecordCategoryType.expense,
      );
      final incomeCategory = await _firstCategory(
        services,
        RecordCategoryType.income,
      );

      expect(
        () => services.expenseService.createExpense(
          ExpenseDraft(
            vehicleId: vehicle.id,
            categoryId: incomeCategory.id,
            eventDateTime: DateTime.utc(2026, 1, 7),
            amountMinor: 100,
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => services.categoryService.createCustomCategory(
          type: RecordCategoryType.expense,
          name: ' ',
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => services.categoryService.createCustomCategory(
          type: RecordCategoryType.expense,
          name: ' ${expenseCategory.name.toLowerCase()} ',
        ),
        throwsA(
          isA<ValidationException>().having(
            (error) => error.message,
            'message',
            contains('already exists'),
          ),
        ),
      );
      final matchingIncomeCategory = await services.categoryService
          .createCustomCategory(
            type: RecordCategoryType.income,
            name: expenseCategory.name,
          );
      expect(matchingIncomeCategory.type, RecordCategoryType.income);
    });
  });

  test(
    'financial aggregation counts service totals once and excludes income',
    () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(_draft(1000));
      final expenseCategory = await _firstCategory(
        services,
        RecordCategoryType.expense,
      );
      final incomeCategory = await _firstCategory(
        services,
        RecordCategoryType.income,
      );

      await services.refuelService.createRefuel(
        _refuelDraft(vehicle.id, odometer: 1100, eventDay: 7),
      );
      await services.expenseService.createExpense(
        ExpenseDraft(
          vehicleId: vehicle.id,
          categoryId: expenseCategory.id,
          eventDateTime: DateTime.utc(2026, 1, 8),
          amountMinor: 2000,
        ),
      );
      await services.incomeService.createIncome(
        IncomeDraft(
          vehicleId: vehicle.id,
          categoryId: incomeCategory.id,
          eventDateTime: DateTime.utc(2026, 1, 9),
          amountMinor: 9999,
        ),
      );
      await services.serviceRecordService.createServiceRecord(
        ServiceRecordDraft(
          vehicleId: vehicle.id,
          eventDateTime: DateTime.utc(2026, 1, 10),
          odometer: 1200,
          totalCostMinor: 24000,
          items: const [
            ServiceItemDraft(itemName: 'Engine Oil', allocatedCostMinor: 12000),
            ServiceItemDraft(itemName: 'Oil Filter', allocatedCostMinor: 4000),
          ],
        ),
      );

      expect(
        await services.financialSummary.monthSpendForVehicle(
          vehicle.id,
          now: DateTime.utc(2026, 1, 20),
        ),
        31000,
      );
    },
  );

  test(
    'unified activity orders records and hides linked odometer duplicates',
    () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(_draft(64000));
      final category = await _firstCategory(
        services,
        RecordCategoryType.expense,
      );

      final refuel = await services.refuelService.createRefuel(
        _refuelDraft(vehicle.id, odometer: 64100, eventDay: 10),
      );
      await services.expenseService.createExpense(
        ExpenseDraft(
          vehicleId: vehicle.id,
          categoryId: category.id,
          eventDateTime: DateTime.utc(2026, 1, 11),
          amountMinor: 2000,
        ),
      );

      final activities = await services.activities.listForVehicle(vehicle.id);

      expect(activities.first.type, DailyActivityType.expense);
      expect(
        activities.where((activity) => activity.recordId == refuel.id),
        hasLength(1),
      );
      expect(
        activities.where(
          (activity) => activity.type == DailyActivityType.odometer,
        ),
        hasLength(1),
      );
    },
  );
}

VehicleDraft _draft(int odometer, {String name = 'Commuter'}) {
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
  required int odometer,
  int totalCostMinor = 5000,
  int volumeMillilitres = 40000,
  int unitPriceMicrosPerLitre = 1250000,
  int eventDay = 7,
}) {
  return RefuelDraft(
    vehicleId: vehicleId,
    eventDateTime: DateTime.utc(2026, 1, eventDay),
    odometer: odometer,
    fuelType: FuelType.petrol,
    totalCostMinor: totalCostMinor,
    volumeMillilitres: volumeMillilitres,
    unitPriceMicrosPerLitre: unitPriceMicrosPerLitre,
    isFullTank: true,
    missedPreviousRefuel: false,
  );
}

Refuel _refuel(
  String id,
  int odometer,
  int volumeMillilitres, {
  bool full = true,
  bool missed = false,
  int? eventMinute,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return Refuel(
    id: id,
    vehicleId: 'vehicle',
    eventDateTime: now.add(Duration(minutes: eventMinute ?? odometer)),
    odometer: odometer,
    fuelType: FuelType.petrol,
    totalCostMinor: 1000,
    volumeMillilitres: volumeMillilitres,
    unitPriceMicrosPerLitre: 1250000,
    isFullTank: full,
    missedPreviousRefuel: missed,
    createdAt: now,
    updatedAt: now,
  );
}

Future<RecordCategory> _firstCategory(
  TestServices services,
  RecordCategoryType type,
) async {
  return (await services.categories.listByType(type)).first;
}

Map<String, Object?> _vehicleMap(String id) {
  return {
    'id': id,
    'name': 'Commuter',
    'make': 'Ford',
    'model': 'Focus',
    'year': null,
    'registration': null,
    'fuel_type': 'PETROL',
    'distance_unit': 'MILES',
    'photo_path': null,
    'trim': null,
    'engine': null,
    'transmission': null,
    'vin': null,
    'colour': null,
    'purchase_date': null,
    'purchase_mileage': null,
    'purchase_price': null,
    'seller': null,
    'notes': null,
    'is_archived': 0,
    'created_at': '2026-01-01T00:00:00.000Z',
    'updated_at': '2026-01-01T00:00:00.000Z',
  };
}

Map<String, Object?> _odometerMap(String id, String vehicleId) {
  return {
    'id': id,
    'vehicle_id': vehicleId,
    'odometer': 64000,
    'event_datetime': '2026-01-01T00:00:00.000Z',
    'source_type': 'MANUAL',
    'source_record_id': null,
    'created_at': '2026-01-01T00:00:00.000Z',
    'updated_at': '2026-01-01T00:00:00.000Z',
  };
}
