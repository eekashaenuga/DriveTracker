import 'dart:io';

import 'package:drivetracker/core/database/app_database.dart';
import 'package:drivetracker/core/database/database_migrations.dart';
import 'package:drivetracker/core/utilities/validation_exception.dart';
import 'package:drivetracker/features/daily_records/domain/daily_activity.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_item.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_reminder.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_reminder_engine.dart';
import 'package:drivetracker/features/maintenance/domain/service_record.dart';
import 'package:drivetracker/features/odometer/domain/odometer_policy.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_services.dart';

void main() {
  test(
    'V2 to latest migration preserves existing data and adds tables',
    () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('drivetracker_v2_');
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final path = p.join(dir.path, 'drive_tracker.db');
      final oldDb = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
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
      await oldDb.insert('refuels', _refuelMap('refuel_1', 'veh_1'));
      await oldDb.insert('expenses', _expenseMap('expense_1', 'veh_1'));
      await oldDb.insert('income_records', _incomeMap('income_1', 'veh_1'));
      await oldDb.close();

      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: path,
      );
      addTearDown(database.close);
      final db = await database.database;

      expect(await db.getVersion(), 4);
      expect((await db.query('vehicles')).single['id'], 'veh_1');
      expect((await db.query('odometer_entries')).single['id'], 'odo_1');
      expect((await db.query('refuels')).single['id'], 'refuel_1');
      expect((await db.query('expenses')).single['id'], 'expense_1');
      expect((await db.query('income_records')).single['id'], 'income_1');
      expect(await db.query('maintenance_items'), isEmpty);
      expect(await db.query('services'), isEmpty);
      expect(await db.query('service_items'), isEmpty);
      expect(await db.query('documents'), isEmpty);
      expect(await db.query('attachments'), isEmpty);
      expect(
        await db.query(
          'sqlite_master',
          where: 'type = ? AND name = ?',
          whereArgs: ['index', 'idx_maintenance_items_active_name'],
        ),
        isNotEmpty,
      );
    },
  );

  group('maintenance reminder engine', () {
    const engine = MaintenanceReminderEngine();
    final asOf = DateTime.utc(2026, 9, 5);

    test('mileage-only interval boundaries are precise', () {
      final item = _item(mileageInterval: 8000);
      final completion = _completion(odometer: 65000);

      expect(
        engine
            .evaluate(
              item: item,
              completions: [completion],
              currentOdometer: 71000,
              asOf: asOf,
            )
            .state,
        MaintenanceReminderState.normal,
      );
      expect(
        engine
            .evaluate(
              item: item,
              completions: [completion],
              currentOdometer: 72000,
              asOf: asOf,
            )
            .state,
        MaintenanceReminderState.upcoming,
      );
      expect(
        engine
            .evaluate(
              item: item,
              completions: [completion],
              currentOdometer: 72700,
              asOf: asOf,
            )
            .state,
        MaintenanceReminderState.dueSoon,
      );
      expect(
        engine
            .evaluate(
              item: item,
              completions: [completion],
              currentOdometer: 73000,
              asOf: asOf,
            )
            .state,
        MaintenanceReminderState.due,
      );
      final overdue = engine.evaluate(
        item: item,
        completions: [completion],
        currentOdometer: 73120,
        asOf: asOf,
      );
      expect(overdue.state, MaintenanceReminderState.overdue);
      expect(overdue.nextMileageDue, 73000);
      expect(overdue.milesRemaining, -120);
    });

    test('date-only interval boundaries are precise', () {
      final item = _item(timeIntervalDays: 365);
      final completion = _completion(eventDateTime: DateTime.utc(2026, 9));

      expect(
        engine
            .evaluate(
              item: item,
              completions: [completion],
              currentOdometer: 70000,
              asOf: DateTime.utc(2027, 7, 15),
            )
            .state,
        MaintenanceReminderState.normal,
      );
      expect(
        engine
            .evaluate(
              item: item,
              completions: [completion],
              currentOdometer: 70000,
              asOf: DateTime.utc(2027, 8, 2),
            )
            .state,
        MaintenanceReminderState.upcoming,
      );
      expect(
        engine
            .evaluate(
              item: item,
              completions: [completion],
              currentOdometer: 70000,
              asOf: DateTime.utc(2027, 8, 25),
            )
            .state,
        MaintenanceReminderState.dueSoon,
      );
      expect(
        engine
            .evaluate(
              item: item,
              completions: [completion],
              currentOdometer: 70000,
              asOf: DateTime.utc(2027, 9),
            )
            .state,
        MaintenanceReminderState.due,
      );
      final overdue = engine.evaluate(
        item: item,
        completions: [completion],
        currentOdometer: 70000,
        asOf: DateTime.utc(2027, 9, 2),
      );
      expect(overdue.state, MaintenanceReminderState.overdue);
      expect(overdue.daysRemaining, -1);
    });

    test('both intervals use the more urgent state', () {
      final item = _item(mileageInterval: 8000, timeIntervalDays: 365);
      final dateDriven = engine.evaluate(
        item: item,
        completions: [
          _completion(odometer: 65000, eventDateTime: DateTime.utc(2026, 9)),
        ],
        currentOdometer: 66000,
        asOf: DateTime.utc(2027, 8, 25),
      );
      expect(dateDriven.state, MaintenanceReminderState.dueSoon);
      expect(dateDriven.primaryBasis, MaintenanceReminderBasis.date);

      final mileageDriven = engine.evaluate(
        item: item,
        completions: [
          _completion(odometer: 65000, eventDateTime: DateTime.utc(2026, 9)),
        ],
        currentOdometer: 73200,
        asOf: DateTime.utc(2027, 8, 2),
      );
      expect(mileageDriven.state, MaintenanceReminderState.overdue);
      expect(mileageDriven.primaryBasis, MaintenanceReminderBasis.mileage);
    });

    test(
      'disabled, archived and interval-free items are not active reminders',
      () {
        final disabled = engine.evaluate(
          item: _item(mileageInterval: 8000, reminderEnabled: false),
          completions: [_completion(odometer: 65000)],
          currentOdometer: 73000,
          asOf: asOf,
        );
        final archived = engine.evaluate(
          item: _item(mileageInterval: 8000, isArchived: true),
          completions: [_completion(odometer: 65000)],
          currentOdometer: 73000,
          asOf: asOf,
        );
        final noInterval = engine.evaluate(
          item: _item(),
          completions: [_completion(odometer: 65000)],
          currentOdometer: 73000,
          asOf: asOf,
        );

        expect(disabled.shouldShowAsReminder, isFalse);
        expect(archived.shouldShowAsReminder, isFalse);
        expect(noInterval.shouldShowAsReminder, isFalse);
        expect(disabled.state, MaintenanceReminderState.normal);
        expect(archived.state, MaintenanceReminderState.normal);
        expect(noInterval.state, MaintenanceReminderState.normal);
      },
    );
  });

  group('maintenance services', () {
    test(
      'create service with multiple items updates odometer and spend once',
      () async {
        final services = createTestServices();
        final vehicle = await services.vehicleService.addVehicle(_draft(64000));
        final oil = await services.maintenanceItemService.createMaintenanceItem(
          MaintenanceItemDraft(
            vehicleId: vehicle.id,
            name: 'Engine Oil',
            mileageInterval: 8000,
          ),
        );
        final filter = await services.maintenanceItemService
            .createMaintenanceItem(
              MaintenanceItemDraft(
                vehicleId: vehicle.id,
                name: 'Oil Filter',
                mileageInterval: 8000,
              ),
            );

        final service = await services.serviceRecordService.createServiceRecord(
          ServiceRecordDraft(
            vehicleId: vehicle.id,
            eventDateTime: DateTime.utc(2026, 9, 5),
            odometer: 66000,
            totalCostMinor: 24000,
            garage: 'ABC Garage',
            items: [
              ServiceItemDraft(
                maintenanceItemId: oil.id,
                itemName: oil.name,
                allocatedCostMinor: 12000,
              ),
              ServiceItemDraft(
                maintenanceItemId: filter.id,
                itemName: filter.name,
                allocatedCostMinor: 4000,
              ),
            ],
          ),
        );

        expect(service.items, hasLength(2));
        expect(
          await services.odometers.currentOdometerForVehicle(vehicle.id),
          66000,
        );
        expect(
          await services.financialSummary.monthSpendForVehicle(
            vehicle.id,
            now: DateTime.utc(2026, 9, 6),
          ),
          24000,
        );
        expect(await services.expenses.listForVehicle(vehicle.id), isEmpty);

        final activities = await services.activities.listForVehicle(
          vehicle.id,
          type: DailyActivityType.service,
        );
        expect(activities.single.title, 'Service');
        expect(activities.single.subtitle, contains('Engine Oil + 1 more'));
        expect(activities.single.amountMinor, 24000);
      },
    );

    test(
      'historical service requires confirmation and does not rewind',
      () async {
        final services = createTestServices();
        final vehicle = await services.vehicleService.addVehicle(_draft(70000));
        final oil = await services.maintenanceItemService.createMaintenanceItem(
          MaintenanceItemDraft(vehicleId: vehicle.id, name: 'Engine Oil'),
        );

        final draft = ServiceRecordDraft(
          vehicleId: vehicle.id,
          eventDateTime: DateTime.utc(2026, 6, 15),
          odometer: 65000,
          totalCostMinor: 9000,
          items: [
            ServiceItemDraft(maintenanceItemId: oil.id, itemName: oil.name),
          ],
        );

        expect(
          () => services.serviceRecordService.createServiceRecord(draft),
          throwsA(isA<OdometerConfirmationRequired>()),
        );

        await services.serviceRecordService.createServiceRecord(
          draft,
          allowHistorical: true,
        );
        expect(
          await services.odometers.currentOdometerForVehicle(vehicle.id),
          70000,
        );
      },
    );

    test(
      'editing and deleting latest service recalculates maintenance due',
      () async {
        final services = createTestServices();
        final vehicle = await services.vehicleService.addVehicle(_draft(50000));
        final oil = await services.maintenanceItemService.createMaintenanceItem(
          MaintenanceItemDraft(
            vehicleId: vehicle.id,
            name: 'Engine Oil',
            mileageInterval: 8000,
          ),
        );

        final older = await services.serviceRecordService.createServiceRecord(
          ServiceRecordDraft(
            vehicleId: vehicle.id,
            eventDateTime: DateTime.utc(2026, 2, 1),
            odometer: 60000,
            totalCostMinor: 8000,
            items: [
              ServiceItemDraft(maintenanceItemId: oil.id, itemName: oil.name),
            ],
          ),
        );
        final latest = await services.serviceRecordService.createServiceRecord(
          ServiceRecordDraft(
            vehicleId: vehicle.id,
            eventDateTime: DateTime.utc(2026, 9, 1),
            odometer: 68000,
            totalCostMinor: 9000,
            items: [
              ServiceItemDraft(maintenanceItemId: oil.id, itemName: oil.name),
            ],
          ),
        );

        var reminders = await services.maintenanceItemService
            .remindersForVehicle(
              vehicle.id,
              currentOdometer: 68000,
              asOf: DateTime.utc(2026, 9, 5),
            );
        expect(reminders.single.nextMileageDue, 76000);
        expect(reminders.single.completions, hasLength(2));

        await services.serviceRecordService.updateServiceRecord(
          latest.record.id,
          ServiceRecordDraft(
            vehicleId: vehicle.id,
            eventDateTime: DateTime.utc(2026, 9, 1),
            odometer: 68000,
            totalCostMinor: 9000,
            items: const [ServiceItemDraft(itemName: 'Inspection')],
          ),
        );
        reminders = await services.maintenanceItemService.remindersForVehicle(
          vehicle.id,
          currentOdometer: 68000,
          asOf: DateTime.utc(2026, 9, 5),
        );
        expect(reminders.single.nextMileageDue, 68000);
        expect(reminders.single.state, MaintenanceReminderState.due);
        expect(reminders.single.completions.single.serviceId, older.record.id);

        await services.serviceRecordService.deleteServiceRecord(
          latest.record.id,
        );
        reminders = await services.maintenanceItemService.remindersForVehicle(
          vehicle.id,
          currentOdometer: 60000,
          asOf: DateTime.utc(2026, 9, 5),
        );
        expect(reminders.single.nextMileageDue, 68000);
        expect(reminders.single.completions.single.serviceId, older.record.id);
      },
    );

    test('baseline completion calculates next due without spend', () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(_draft(65000));
      final oil = await services.maintenanceItemService.createMaintenanceItem(
        MaintenanceItemDraft(
          vehicleId: vehicle.id,
          name: 'Engine Oil',
          mileageInterval: 8000,
          timeIntervalDays: 365,
        ),
      );

      await services.serviceRecordService.createBaselineCompletion(
        item: oil,
        eventDateTime: DateTime.utc(2026, 6, 15),
        odometer: 64500,
      );

      final reminders = await services.maintenanceItemService
          .remindersForVehicle(
            vehicle.id,
            currentOdometer: 65000,
            asOf: DateTime.utc(2026, 9, 5),
          );
      expect(reminders.single.nextMileageDue, 72500);
      expect(reminders.single.nextDateDue, DateTime.utc(2027, 6, 15));
      expect(reminders.single.milesRemaining, 7500);
      expect(
        await services.financialSummary.monthSpendForVehicle(
          vehicle.id,
          now: DateTime.utc(2026, 6, 20),
        ),
        0,
      );

      final activities = await services.activities.listForVehicle(
        vehicle.id,
        type: DailyActivityType.service,
      );
      expect(activities.single.title, 'Maintenance baseline');
      expect(activities.single.amountMinor, isNull);
    });

    test(
      'vehicle isolation keeps items, services and reminders separate',
      () async {
        final services = createTestServices();
        final vehicleA = await services.vehicleService.addVehicle(
          _draft(65000, name: 'Commuter'),
        );
        final vehicleB = await services.vehicleService.addVehicle(
          _draft(20000, name: 'Weekend'),
        );
        final oilA = await services.maintenanceItemService
            .createMaintenanceItem(
              MaintenanceItemDraft(
                vehicleId: vehicleA.id,
                name: 'Engine Oil',
                mileageInterval: 8000,
              ),
            );
        await services.maintenanceItemService.createMaintenanceItem(
          MaintenanceItemDraft(
            vehicleId: vehicleB.id,
            name: 'Engine Oil',
            mileageInterval: 8000,
          ),
        );

        await services.serviceRecordService.createServiceRecord(
          ServiceRecordDraft(
            vehicleId: vehicleA.id,
            eventDateTime: DateTime.utc(2026, 9, 5),
            odometer: 66000,
            totalCostMinor: 12000,
            items: [
              ServiceItemDraft(maintenanceItemId: oilA.id, itemName: oilA.name),
            ],
          ),
        );

        final aReminders = await services.maintenanceItemService
            .remindersForVehicle(
              vehicleA.id,
              currentOdometer: 66000,
              asOf: DateTime.utc(2026, 9, 5),
            );
        final bReminders = await services.maintenanceItemService
            .remindersForVehicle(
              vehicleB.id,
              currentOdometer: 20000,
              asOf: DateTime.utc(2026, 9, 5),
            );
        expect(aReminders.single.nextMileageDue, 74000);
        expect(bReminders.single.nextMileageDue, isNull);
        expect(
          await services.serviceRecords.listForVehicle(vehicleB.id),
          isEmpty,
        );
      },
    );

    test('archive removes active reminder and preserves history', () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(_draft(65000));
      final oil = await services.maintenanceItemService.createMaintenanceItem(
        MaintenanceItemDraft(
          vehicleId: vehicle.id,
          name: 'Engine Oil',
          mileageInterval: 8000,
        ),
      );
      await services.serviceRecordService.createServiceRecord(
        ServiceRecordDraft(
          vehicleId: vehicle.id,
          eventDateTime: DateTime.utc(2026, 9, 5),
          odometer: 66000,
          totalCostMinor: 12000,
          items: [
            ServiceItemDraft(maintenanceItemId: oil.id, itemName: oil.name),
          ],
        ),
      );

      await services.maintenanceItemService.archiveMaintenanceItem(oil.id);

      expect(
        await services.maintenanceItemService.remindersForVehicle(
          vehicle.id,
          currentOdometer: 66000,
          asOf: DateTime.utc(2026, 9, 5),
        ),
        isEmpty,
      );
      final history = await services.maintenanceItemService
          .completionHistoryForItem(vehicle.id, oil.id);
      expect(history, hasLength(1));
      expect(history.single.itemName, 'Engine Oil');
    });

    test('maintenance item validation trims and rejects duplicates', () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(_draft(65000));
      final item = await services.maintenanceItemService.createMaintenanceItem(
        MaintenanceItemDraft(
          vehicleId: vehicle.id,
          name: '  Engine Oil  ',
          mileageInterval: 8000,
        ),
      );

      expect(item.name, 'Engine Oil');
      expect(
        () => services.maintenanceItemService.createMaintenanceItem(
          MaintenanceItemDraft(vehicleId: vehicle.id, name: 'engine oil'),
        ),
        throwsA(
          isA<ValidationException>().having(
            (error) => error.message,
            'message',
            contains('already exists'),
          ),
        ),
      );
      expect(
        () => services.maintenanceItemService.createMaintenanceItem(
          MaintenanceItemDraft(
            vehicleId: vehicle.id,
            name: 'Cabin Filter',
            mileageInterval: 0,
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => services.maintenanceItemService.createMaintenanceItem(
          MaintenanceItemDraft(
            vehicleId: vehicle.id,
            name: 'Air Filter',
            mileageWarning: -1,
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}

MaintenanceItem _item({
  String id = 'maint_1',
  String vehicleId = 'veh_1',
  String name = 'Engine Oil',
  int? mileageInterval,
  int? timeIntervalDays,
  int mileageWarning = 1000,
  int dateWarningDays = 30,
  bool reminderEnabled = true,
  bool isArchived = false,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return MaintenanceItem(
    id: id,
    vehicleId: vehicleId,
    name: name,
    mileageInterval: mileageInterval,
    timeIntervalDays: timeIntervalDays,
    mileageWarning: mileageWarning,
    dateWarningDays: dateWarningDays,
    reminderEnabled: reminderEnabled,
    isArchived: isArchived,
    createdAt: now,
    updatedAt: now,
  );
}

MaintenanceCompletion _completion({
  String serviceId = 'service_1',
  String serviceItemId = 'service_item_1',
  String maintenanceItemId = 'maint_1',
  String itemName = 'Engine Oil',
  DateTime? eventDateTime,
  int? odometer,
  bool isBaseline = false,
}) {
  final event = eventDateTime ?? DateTime.utc(2026, 1, 1);
  return MaintenanceCompletion(
    serviceId: serviceId,
    serviceItemId: serviceItemId,
    maintenanceItemId: maintenanceItemId,
    itemName: itemName,
    eventDateTime: event,
    createdAt: event,
    odometer: odometer,
    isBaseline: isBaseline,
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

Map<String, Object?> _refuelMap(String id, String vehicleId) {
  return {
    'id': id,
    'vehicle_id': vehicleId,
    'event_datetime': '2026-01-02T00:00:00.000Z',
    'odometer': 64100,
    'fuel_type': 'PETROL',
    'total_cost_minor': 5000,
    'volume_millilitres': 40000,
    'unit_price_micros_per_litre': 1250000,
    'is_full_tank': 1,
    'missed_previous_refuel': 0,
    'station': 'ABC Fuel',
    'notes': null,
    'created_at': '2026-01-02T00:00:00.000Z',
    'updated_at': '2026-01-02T00:00:00.000Z',
  };
}

Map<String, Object?> _expenseMap(String id, String vehicleId) {
  return {
    'id': id,
    'vehicle_id': vehicleId,
    'category_id': 'cat_expense_insurance',
    'event_datetime': '2026-01-03T00:00:00.000Z',
    'odometer': null,
    'amount_minor': 1200,
    'merchant': 'Insurer',
    'payment_method': null,
    'notes': null,
    'created_at': '2026-01-03T00:00:00.000Z',
    'updated_at': '2026-01-03T00:00:00.000Z',
  };
}

Map<String, Object?> _incomeMap(String id, String vehicleId) {
  return {
    'id': id,
    'vehicle_id': vehicleId,
    'category_id': 'cat_income_rideshare',
    'event_datetime': '2026-01-04T00:00:00.000Z',
    'odometer': null,
    'amount_minor': 4500,
    'source': 'Rideshare',
    'notes': null,
    'created_at': '2026-01-04T00:00:00.000Z',
    'updated_at': '2026-01-04T00:00:00.000Z',
  };
}
