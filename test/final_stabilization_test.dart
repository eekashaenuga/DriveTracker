import 'dart:io';

import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/app/theme/dt_theme.dart';
import 'package:drivetracker/core/database/database_migrations.dart';
import 'package:drivetracker/features/attachments/domain/attachment.dart';
import 'package:drivetracker/features/attachments/domain/attachment_io.dart';
import 'package:drivetracker/features/daily_records/domain/expense.dart';
import 'package:drivetracker/features/daily_records/domain/record_category.dart';
import 'package:drivetracker/features/data_safety/domain/data_safety_service.dart';
import 'package:drivetracker/features/documents/domain/vehicle_document.dart';
import 'package:drivetracker/features/insights/presentation/insights_screen.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_item.dart';
import 'package:drivetracker/features/reminders/domain/date_reminder_schedule.dart';
import 'package:drivetracker/features/reminders/domain/reminder_notification_scheduler.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/test_services.dart';
import 'notification_scheduler_test.dart' show FakeLocalNotificationClient;

final _now = DateTime(2026, 10, 21, 12);
VehicleDraft _draft(String name, double price) => VehicleDraft(
  name: name,
  make: 'Ford',
  model: 'Focus',
  fuelType: FuelType.petrol,
  distanceUnit: DistanceUnit.miles,
  currentOdometer: 1000,
  purchasePrice: price,
  purchaseDate: DateTime(2026, 10, 1),
);
ManagedAttachmentStorage _storage(TestServices s) =>
    ManagedAttachmentStorage(rootDirectory: () async => s.attachmentRoot);

void main() {
  testWidgets('Insights archive fallback displays the same scope it queries', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 760));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final s = createTestServices();
    late Vehicle selected;
    await tester.runAsync(() async {
      await s.vehicleService.addVehicle(_draft('Remaining', 200));
      selected = await s.vehicleService.addVehicle(_draft('Archive me', 100));
    });
    final controller = DriveTrackerController(
      database: s.database,
      clock: () => _now,
      attachmentStorage: _storage(s),
      attachmentPicker: s.attachmentPicker,
      attachmentOpener: s.attachmentOpener,
    );
    await tester.runAsync(controller.initialize);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: DTTheme.light(),
          home: const InsightsScreen(),
        ),
      ),
    );
    Finder amount(String text) => find.descendant(
      of: find.byKey(const Key('insightsAcquisitionMetric')),
      matching: find.text(text),
    );
    await _waitFor(tester, amount('£100.00'));
    await tester.runAsync(() => controller.archiveVehicle(selected.id));
    await _waitFor(tester, amount('£200.00'));
    expect(
      find.descendant(
        of: find.byKey(const Key('insightsVehicleSelector')),
        matching: find.text('All vehicles'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: DTTheme.light(),
          darkTheme: DTTheme.dark(),
          themeMode: ThemeMode.dark,
          home: const InsightsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(amount('£200.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  test('Current-schema format-1 backup preserves combined V1.1 data and rebuildable schedules after reopen', () async {
    final source = createTestServices();
    final vehicle = await source.vehicleService.addVehicle(
      _draft('Owned vehicle', 3000.55),
    );
    final category = await source.categoryService.createCustomCategory(
      type: RecordCategoryType.expense,
      name: 'Special parking',
    );
    await source.expenseService.createExpense(
      ExpenseDraft(
        vehicleId: vehicle.id,
        categoryId: category.id,
        eventDateTime: DateTime(2026, 10, 2),
        amountMinor: 1234,
      ),
    );
    await source.categoryService.setArchived(category.id, true);
    const timing = DateReminderSchedule(
      offsets: [ReminderOffset(7), ReminderOffset(1)],
      dailyFromDays: 2,
    );
    await source.maintenanceItemService.createMaintenanceItem(
      MaintenanceItemDraft(
        vehicleId: vehicle.id,
        name: 'MOT',
        category: 'MOT',
        kind: MaintenanceRecordKind.expiry,
        expiryDate: DateTime(2026, 11, 1),
        reminderSchedule: timing,
      ),
    );
    final oil = await source.maintenanceItemService.createMaintenanceItem(
      MaintenanceItemDraft(
        vehicleId: vehicle.id,
        name: 'Oil',
        mileageInterval: 8000,
        timeIntervalDays: 365,
      ),
    );
    await source.serviceRecordService.createBaselineCompletion(
      item: oil,
      eventDateTime: DateTime(2026, 10, 1),
      odometer: 1000,
    );
    final document = await source.documentService.createDocument(
      VehicleDocumentDraft(
        vehicleId: vehicle.id,
        category: 'Insurance',
        title: 'Policy',
        expiryDate: DateTime(2026, 11, 15),
      ),
    );
    final dir = await Directory.systemTemp.createTemp('vehnora_final_backup_');
    addTearDown(() => dir.delete(recursive: true));
    final attachments = <Attachment>[];
    for (final ext in ['pdf', 'png']) {
      final bytes = ext == 'pdf'
          ? [37, 80, 68, 70, 45, 49]
          : [137, 80, 78, 71, 13, 10, 26, 10];
      final file = await File('${dir.path}/source.$ext').writeAsBytes(bytes);
      attachments.add(
        await source.attachmentService.addAttachment(
          parentType: AttachmentParentType.document,
          parentId: document.id,
          source: AttachmentSource(
            sourcePath: file.path,
            fileName: 'source.$ext',
            mimeType: ext == 'pdf' ? 'application/pdf' : 'image/png',
            fileSize: bytes.length,
          ),
        ),
      );
    }
    final before = <String, List<Map<String, Object?>>>{};
    final db = await source.database.database;
    for (final table in DatabaseMigrations.requiredTablesFor(
      DatabaseMigrations.schemaVersion,
    )) {
      before[table] = await db.query(table);
    }
    DataSafetyService safety(TestServices s) =>
        DataSafetyService(database: s.database, attachmentStorage: _storage(s));
    final backup = await safety(source).createBackup(outputDirectory: dir);
    expect(backup.file.path, endsWith('.dtbackup'));
    final inspected = await safety(source).inspectBackupFile(backup.file.path);
    expect(inspected.manifest.backupFormatVersion, 1);
    expect(inspected.manifest.schemaVersion, DatabaseMigrations.schemaVersion);
    expect(inspected.manifest.attachments, hasLength(2));
    final target = createTestServices();
    await safety(target).restoreBackupFromFile(backup.file.path);
    await target.database.close();
    final reopened = await target.database.database;
    expect(await reopened.rawQuery('PRAGMA user_version'), [
      {'user_version': DatabaseMigrations.schemaVersion},
    ]);
    expect(await reopened.rawQuery('PRAGMA integrity_check'), [
      {'integrity_check': 'ok'},
    ]);
    expect(await reopened.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    for (final table in before.keys) {
      expect(
        await reopened.query(table),
        before[table],
        reason: '$table must survive backup/restore/reopen',
      );
    }
    expect(
      (await target.vehicles.getById(vehicle.id))!.acquisitionCostMinor,
      300055,
    );
    for (final attachment in attachments) {
      final original = File(
        await _storage(source).resolveAbsolutePath(attachment.storedPath),
      );
      final restored = File(
        await _storage(target).resolveAbsolutePath(attachment.storedPath),
      );
      expect(await restored.readAsBytes(), await original.readAsBytes());
    }
    ReminderNotificationScheduler scheduler(TestServices s) =>
        ReminderNotificationScheduler(
          client: FakeLocalNotificationClient(),
          vehicleRepository: s.vehicles,
          odometerRepository: s.odometers,
          maintenanceItemService: s.maintenanceItemService,
          documentRepository: s.documents,
          clock: () => _now,
        );
    final originalRequests = await scheduler(source)
        .buildDateReminderRequests();
    final restoredRequests = await scheduler(target)
        .buildDateReminderRequests();
    expect(restoredRequests, isNotEmpty);
    expect(
      restoredRequests.map(
        (r) => (r.id, r.stableId, r.scheduledAt, r.title, r.body),
      ),
      originalRequests.map(
        (r) => (r.id, r.stableId, r.scheduledAt, r.title, r.body),
      ),
    );
    expect(restoredRequests.every((r) => r.scheduledAt.isAfter(_now)), isTrue);
  });
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsOneWidget);
}
