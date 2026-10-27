import 'package:drivetracker/features/data_safety/domain/backup_manifest.dart';

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:drivetracker/core/calculations/analytics_date_range.dart';
import 'package:drivetracker/features/attachments/domain/attachment.dart';
import 'package:drivetracker/features/attachments/domain/attachment_io.dart';
import 'package:drivetracker/features/data_safety/domain/data_safety_service.dart';

import 'dart:io';

import 'package:drivetracker/core/database/app_database.dart';
import 'package:drivetracker/core/database/database_migrations.dart';
import 'package:drivetracker/core/utilities/validation_exception.dart';
import 'package:drivetracker/features/daily_records/domain/income.dart';
import 'package:drivetracker/features/daily_records/domain/income_activity.dart';
import 'package:drivetracker/features/daily_records/domain/income_earnings.dart';
import 'package:drivetracker/features/daily_records/domain/expense.dart';
import 'package:drivetracker/features/daily_records/domain/record_category.dart';
import 'package:drivetracker/features/daily_records/data/income_activity_expense_repository.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_services.dart';

const vehicleDraft = VehicleDraft(
  name: 'Work car',
  make: 'Ford',
  model: 'Focus',
  fuelType: FuelType.petrol,
  distanceUnit: DistanceUnit.miles,
  currentOdometer: 1000,
);
IncomeDraft activityDraft(
  String vehicleId, {
  IncomeActivity activity = const IncomeActivity(
    type: IncomeActivityType.delivery,
  ),
  List<String>? ids,
  List<ExpenseDraft> expenses = const [],
  String category = 'cat_income_delivery',
  int amount = 10000,
}) => IncomeDraft(
  vehicleId: vehicleId,
  categoryId: category,
  eventDateTime: DateTime(2026, 10, 1),
  amountMinor: amount,
  activity: activity,
  linkedExpenseIds: ids,
  newDirectExpenses: expenses,
);
ExpenseDraft cost(String vehicleId, int amount) => ExpenseDraft(
  vehicleId: vehicleId,
  categoryId: 'cat_expense_parking',
  eventDateTime: DateTime(2026, 10, 1),
  amountMinor: amount,
);

void main() {
  test('V5 to V6 preserves legacy income and attachment metadata; fresh V6 validates', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('income_v5_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/legacy.db';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: DatabaseMigrations.createSchema,
      ),
    );
    await old.insert('vehicles', {
      'id': 'v',
      'name': 'Old',
      'make': 'Ford',
      'model': 'Focus',
      'fuel_type': 'PETROL',
      'distance_unit': 'MILES',
      'created_at': '2026-01-01',
      'updated_at': '2026-01-01',
    });
    final record = {
      'id': 'income_old',
      'vehicle_id': 'v',
      'category_id': 'cat_income_rideshare',
      'event_datetime': '2026-01-01T12:00:00Z',
      'amount_minor': 12345,
      'odometer': 1000,
      'source': 'Original',
      'notes': 'Keep',
      'created_at': '2026-01-01',
      'updated_at': '2026-01-01',
    };
    await old.insert('income_records', record);
    await old.insert('attachments', {
      'id': 'a',
      'parent_type': 'INCOME',
      'parent_id': 'income_old',
      'file_name': 'receipt.pdf',
      'stored_path': 'income/receipt.pdf',
      'file_size': 10,
      'created_at': '2026-01-01',
      'updated_at': '2026-01-01',
    });
    final attachments = await old.query('attachments');
    await old.close();
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: path,
    );
    addTearDown(database.close);
    final upgraded = await database.database;
    expect(await DatabaseMigrations.validateSchema(upgraded), 6);
    final row = (await upgraded.query('income_records')).single;
    for (final field in record.entries) {
      expect(row[field.key], field.value);
    }
    final income = Income.fromMap(row);
    expect(income.activity.type, IncomeActivityType.simple);
    expect(income.activity.distanceMm, isNull);
    expect(income.activity.baseMinor, isNull);
    expect(income.activity.directCostsComplete, isFalse);
    expect(await upgraded.query('attachments'), attachments);
    expect(await upgraded.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    final fresh = createTestServices();
    expect(
      await DatabaseMigrations.validateSchema(await fresh.database.database),
      6,
    );
  });
  test('format-1 V5 backup restores legacy income through migration', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('income_v5_backup_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/old.db';
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: DatabaseMigrations.createSchema,
      ),
    );
    await db.insert('vehicles', {
      'id': 'v',
      'name': 'Old',
      'make': 'Ford',
      'model': 'Focus',
      'fuel_type': 'PETROL',
      'distance_unit': 'MILES',
      'created_at': '2026-01-01',
      'updated_at': '2026-01-01',
    });
    await db.insert('income_records', {
      'id': 'legacy',
      'vehicle_id': 'v',
      'category_id': 'cat_income_delivery',
      'event_datetime': '2026-01-01',
      'amount_minor': 1234,
      'source': 'Payer',
      'notes': 'Original',
      'created_at': '2026-01-01',
      'updated_at': '2026-01-01',
    });
    final counts = <String, int>{};
    for (final table in DatabaseMigrations.requiredTablesFor(5)) {
      counts[table] = (await db.query(table)).length;
    }
    await db.close();
    final bytes = await File(path).readAsBytes();
    final manifest = BackupManifest(
      backupFormatVersion: 1,
      schemaVersion: 5,
      createdAtUtc: DateTime.utc(2026),
      databasePath: DataSafetyService.databaseArchivePath,
      databaseBytes: bytes.length,
      tableCounts: counts,
      attachments: const [],
    );
    final archive = Archive()
      ..add(
        ArchiveFile.string(
          DataSafetyService.manifestPath,
          jsonEncode(manifest.toJson()),
        ),
      )
      ..add(
        ArchiveFile(DataSafetyService.databaseArchivePath, bytes.length, bytes),
      );
    final file = await File('${dir.path}/old.dtbackup')
        .writeAsBytes(ZipEncoder().encodeBytes(archive));
    final target = createTestServices();
    final safety = DataSafetyService(
      database: target.database,
      attachmentStorage: ManagedAttachmentStorage(
        rootDirectory: () async => target.attachmentRoot,
      ),
    );
    expect(
      (await safety.inspectBackupFile(file.path)).manifest.schemaVersion,
      5,
    );
    await safety.restoreBackupFromFile(file.path);
    final restored = (await target.incomes.getById('legacy'))!;
    expect(restored.amountMinor, 1234);
    expect(restored.source, 'Payer');
    expect(restored.notes, 'Original');
    expect(restored.activity.type, IncomeActivityType.simple);
    expect(restored.activity.distanceMm, isNull);
    expect(
      await DatabaseMigrations.validateSchema(await target.database.database),
      6,
    );
  });
  test('optional breakdown requires explicit zeroes and exact gross', () {
    const IncomeActivity().validate(100);
    expect(
      () => const IncomeActivity(
        type: IncomeActivityType.delivery,
        baseMinor: 100,
      ).validate(100),
      throwsA(isA<ValidationException>()),
    );
    const IncomeActivity(
      type: IncomeActivityType.delivery,
      baseMinor: 100,
      tipsMinor: 0,
      travelMinor: 0,
      otherMinor: 0,
    ).validate(100);
    expect(
      () => const IncomeActivity(
        type: IncomeActivityType.delivery,
        baseMinor: 99,
        tipsMinor: 0,
        travelMinor: 0,
        otherMinor: 0,
      ).validate(100),
      throwsA(isA<ValidationException>()),
    );
  });
  test('distance, duration, count and reimbursement validation', () {
    for (final a in [
      const IncomeActivity(type: IncomeActivityType.delivery, distanceMm: 0),
      const IncomeActivity(
        type: IncomeActivityType.delivery,
        durationMinutes: 0,
      ),
      const IncomeActivity(
        type: IncomeActivityType.delivery,
        deliveryCount: -1,
      ),
      const IncomeActivity(type: IncomeActivityType.work, deliveryCount: 1),
      const IncomeActivity(
        type: IncomeActivityType.reimbursement,
        rateMicros: 450000,
      ),
    ]) {
      expect(() => a.validate(100), throwsA(isA<ValidationException>()));
    }
  });
  test('canonical activity distance and contractual unit survive display unit changes', () async {
    final s = createTestServices();
    final v = await s.vehicleService.addVehicle(vehicleDraft);
    final mm = ActivityDistance.parse('12.345', DistanceUnit.miles)!;
    expect(ActivityDistance.input(mm, DistanceUnit.miles), '12.345');
    final before = await s.odometers.allForVehicle(v.id);
    final r = await s.incomeService.createIncome(
      activityDraft(
        v.id,
        activity: IncomeActivity(
          type: IncomeActivityType.reimbursement,
          distanceMm: mm,
          rateMicros: 450000,
          rateUnit: DistanceUnit.miles,
        ),
      ),
    );
    await s.vehicleService.updateVehicleDistanceUnit(
      v.id,
      DistanceUnit.kilometers,
    );
    final changed = (await s.incomes.getById(r.id))!;
    expect(changed.activity.distanceMm, mm);
    expect(changed.activity.rateUnit, DistanceUnit.miles);
    expect((await s.odometers.allForVehicle(v.id)).length, before.length);
    expect(ActivityDistance.parse('1.000', DistanceUnit.kilometers), 1000000);
    expect(IncomeEarnings(changed, 0).expectedClaimMinor, 556);
  });
  test(
    'earnings allow negative net and unknown costs remain unknown',
    () async {
      final s = createTestServices();
      final v = await s.vehicleService.addVehicle(vehicleDraft);
      final r = await s.incomeService.createIncome(
        activityDraft(
          v.id,
          activity: const IncomeActivity(
            type: IncomeActivityType.delivery,
            distanceMm: 16093440,
            durationMinutes: 120,
            deliveryCount: 4,
            directCostsComplete: true,
          ),
        ),
      );
      final e = IncomeEarnings(r, 12000);
      expect(e.netMinor, -2000);
      expect(e.grossPerDistance(DistanceUnit.miles), 1000);
      expect(e.netPerDistance(DistanceUnit.miles), -200);
      expect(e.grossPerHour, 5000);
      expect(e.netPerHour, -1000);
      expect(e.perDelivery, 2500);
      final unknown = await s.incomeService.createIncome(activityDraft(v.id));
      expect(IncomeEarnings(unknown, 0).netMinor, isNull);
    },
  );
  test(
    'weighted aggregates use matching eligible records and expose coverage',
    () async {
      final s = createTestServices();
      final v = await s.vehicleService.addVehicle(vehicleDraft);
      final records = <IncomeEarnings>[];
      for (final pair in [(10000, 60), (20000, 180), (90000, null)]) {
        final r = await s.incomeService.createIncome(
          activityDraft(
            v.id,
            amount: pair.$1,
            activity: IncomeActivity(
              type: IncomeActivityType.delivery,
              durationMinutes: pair.$2,
              directCostsComplete: true,
            ),
          ),
        );
        records.add(IncomeEarnings(r, 0));
      }
      final summary = EarningsSummary(records);
      expect(summary.perHour(), 7500);
      expect(summary.durationCount, 2);
      expect(summary.count, 3);
      expect(summary.netMinor, 120000);
    },
  );
  test(
    'same ID edits and category lifecycle never infer template changes',
    () async {
      final s = createTestServices();
      final v = await s.vehicleService.addVehicle(vehicleDraft);
      final c = await s.categoryService.createCustomCategory(
        type: RecordCategoryType.income,
        name: 'Custom',
      );
      final r = await s.incomeService.createIncome(
        activityDraft(v.id, category: c.id),
      );
      await s.categoryService.rename(c.id, 'Renamed');
      await s.categoryService.setArchived(c.id, true);
      final updated = await s.incomeService.updateIncome(
        r.id,
        activityDraft(v.id, category: c.id, amount: 20000),
      );
      expect(updated.id, r.id);
      expect(updated.createdAt, r.createdAt);
      expect(updated.activity.type, IncomeActivityType.delivery);
      expect(await s.incomes.listForVehicle(v.id), hasLength(1));
    },
  );
  test(
    'Insights preserves totals and refreshes costs without double subtraction',
    () async {
      final s = createTestServices();
      final v = await s.vehicleService.addVehicle(vehicleDraft);
      final r = await s.incomeService.createIncome(
        activityDraft(
          v.id,
          activity: const IncomeActivity(
            type: IncomeActivityType.delivery,
            directCostsComplete: true,
          ),
          expenses: [cost(v.id, 1200)],
        ),
      );
      final before = await s.insights.loadInsights(
        vehicleId: v.id,
        range: AnalyticsDateRange.all,
      );
      expect(before.incomeMinor, 10000);
      expect(before.totalSpendMinor, 1200);
      expect(before.netMinor, 8800);
      expect(before.incomeActivities.single.netMinor, 8800);
      final expense = (await IncomeActivityExpenseRepository(
        s.database,
      ).linked(r.id)).single;
      await s.expenseService.updateExpense(expense.id, cost(v.id, 2000));
      final after = await s.insights.loadInsights(
        vehicleId: v.id,
        range: AnalyticsDateRange.all,
      );
      expect(after.netMinor, 8000);
      expect(after.incomeActivities.single.netMinor, 8000);
      final outside = await s.insights.loadInsights(
        vehicleId: v.id,
        range: AnalyticsDateRange.custom(
          start: DateTime(2026, 11),
          endInclusive: DateTime(2026, 11, 30),
        ),
      );
      expect(outside.incomeActivities, isEmpty);
    },
  );
  test('V6 backup attachment relationship and CSV round trip', () async {
    final s = createTestServices();
    final v = await s.vehicleService.addVehicle(vehicleDraft);
    final r = await s.incomeService.createIncome(
      activityDraft(
        v.id,
        activity: const IncomeActivity(
          type: IncomeActivityType.delivery,
          distanceMm: 12345678,
          durationMinutes: 75,
          deliveryCount: 8,
          directCostsComplete: true,
        ),
        expenses: [cost(v.id, 500)],
      ),
    );
    final dir = await Directory.systemTemp.createTemp('income_backup_');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('${dir.path}/receipt.pdf')
        .writeAsBytes([37, 80, 68, 70]);
    final attachment = await s.attachmentService.addAttachment(
      parentType: AttachmentParentType.income,
      parentId: r.id,
      source: AttachmentSource(
        sourcePath: file.path,
        fileName: 'receipt.pdf',
        mimeType: 'application/pdf',
      ),
    );
    ManagedAttachmentStorage storage(TestServices t) =>
        ManagedAttachmentStorage(rootDirectory: () async => t.attachmentRoot);
    DataSafetyService safety(TestServices t) =>
        DataSafetyService(database: t.database, attachmentStorage: storage(t));
    final backup = await safety(s).createBackup(outputDirectory: dir);
    final manifest = (await safety(s).inspectBackupFile(backup.file.path))
        .manifest;
    expect(manifest.schemaVersion, 6);
    expect(manifest.backupFormatVersion, 1);
    final target = createTestServices();
    await safety(target).restoreBackupFromFile(backup.file.path);
    await target.database.close();
    final restored = (await target.incomes.getById(r.id))!;
    expect(restored.toMap(), r.toMap());
    expect(
      (await IncomeActivityExpenseRepository(target.database)
              .earnings(restored))
          .directCostsMinor,
      500,
    );
    expect(
      await File(
        await storage(target).resolveAbsolutePath(attachment.storedPath),
      ).readAsBytes(),
      [37, 80, 68, 70],
    );
    final csv = await safety(s).createCsvExport(outputDirectory: dir);
    final zip = ZipDecoder().decodeBytes(await csv.file.readAsBytes());
    final incomeCsv = utf8.decode(
      zip.find('csv/income_records.csv')!.readBytes()!,
    );
    expect(incomeCsv, contains('activity_distance_mm'));
    expect(incomeCsv, contains('delivery'));
    expect(incomeCsv, contains('12345678'));
    final links = utf8.decode(
      zip.find('csv/income_activity_expenses.csv')!.readBytes()!,
    );
    expect(links, contains(r.id));
    expect(
      await (await target.database.database).rawQuery(
        'PRAGMA foreign_key_check',
      ),
      isEmpty,
    );
  });
  test('direct expense creation is atomic; link uniqueness and same vehicle enforced', () async {
    final s = createTestServices();
    final v = await s.vehicleService.addVehicle(vehicleDraft);
    final other = await s.vehicleService.addVehicle(vehicleDraft);
    final e = await s.expenseService.createExpense(cost(v.id, 500));
    final foreign = await s.expenseService.createExpense(cost(other.id, 600));
    final r = await s.incomeService.createIncome(
      activityDraft(v.id, ids: [e.id], expenses: [cost(v.id, 700)]),
    );
    final repo = IncomeActivityExpenseRepository(s.database);
    expect(await repo.linked(r.id), hasLength(2));
    expect((await repo.earnings(r)).directCostsMinor, 1200);
    for (final ids in [
      [e.id],
      [foreign.id],
    ]) {
      await expectLater(
        s.incomeService.createIncome(
          activityDraft(v.id, ids: ids, expenses: [cost(v.id, 100)]),
        ),
        throwsA(isA<ValidationException>()),
      );
    }
    expect(await s.incomes.listForVehicle(v.id), hasLength(1));
    expect(await s.expenses.listForVehicle(v.id), hasLength(2));
  });
  test('unlink distinct from delete; expense edits refresh net; income deletion retains expenses', () async {
    final s = createTestServices();
    final v = await s.vehicleService.addVehicle(vehicleDraft);
    final e = await s.expenseService.createExpense(cost(v.id, 500));
    const a = IncomeActivity(
      type: IncomeActivityType.delivery,
      directCostsComplete: true,
    );
    final r = await s.incomeService.createIncome(
      activityDraft(v.id, ids: [e.id], activity: a),
    );
    final repo = IncomeActivityExpenseRepository(s.database);
    await expectLater(
      s.expenseService.deleteExpense(e.id),
      throwsA(isA<ValidationException>()),
    );
    await s.expenseService.updateExpense(e.id, cost(v.id, 1500));
    expect((await repo.earnings(r)).netMinor, 8500);
    await s.incomeService.updateIncome(
      r.id,
      activityDraft(v.id, ids: [], activity: a),
    );
    expect(await repo.linked(r.id), isEmpty);
    expect(await s.expenses.getById(e.id), isNotNull);
    await s.incomeService.updateIncome(
      r.id,
      activityDraft(v.id, ids: [e.id], activity: a),
    );
    await s.incomeService.deleteIncome(r.id);
    expect(await s.expenses.getById(e.id), isNotNull);
    expect(await repo.linked(r.id), isEmpty);
  });
}
