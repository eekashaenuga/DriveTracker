import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/app/theme/dt_theme.dart';
import 'package:drivetracker/core/database/app_database.dart';
import 'package:drivetracker/core/database/database_migrations.dart';
import 'package:drivetracker/core/notifications/local_notification_service.dart';
import 'package:drivetracker/core/utilities/validation_exception.dart';
import 'package:drivetracker/features/attachments/domain/attachment_io.dart';
import 'package:drivetracker/features/data_safety/domain/backup_manifest.dart';
import 'package:drivetracker/features/data_safety/domain/data_safety_service.dart';
import 'package:drivetracker/features/documents/domain/vehicle_document.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_item.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_reminder.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_reminder_engine.dart';
import 'package:drivetracker/features/maintenance/domain/service_record.dart';
import 'package:drivetracker/features/maintenance/presentation/maintenance_item_form_screen.dart';
import 'package:drivetracker/features/reminders/domain/date_reminder_schedule.dart';
import 'package:drivetracker/features/reminders/domain/reminder_notification_scheduler.dart';
import 'package:drivetracker/features/reminders/domain/reminder_overview.dart';
import 'package:drivetracker/features/reminders/domain/reminder_wording.dart';
import 'package:drivetracker/features/reminders/presentation/reminders_screen.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_services.dart';
import 'notification_scheduler_test.dart' show FakeLocalNotificationClient;

void main() {
  test('MOT preset uses calendar months and deduplicates day seven', () {
    final dates = DateReminderSchedule.mot.notificationTimes(
      DateTime(2027, 3, 31),
      DateTime(2026),
    );
    expect(dates, hasLength(11));
    expect(
      dates,
      containsAll([
        DateTime(2026, 12, 31, 9),
        DateTime(2027, 2, 28, 9),
        DateTime(2027, 3, 16, 9),
      ]),
    );
    expect(dates.where((d) => d == DateTime(2027, 3, 24, 9)), hasLength(1));
    expect(dates.last, DateTime(2027, 3, 31, 9));
  });

  test(
    'custom timing round trips, excludes past and respects calendar DST dates',
    () {
      const schedule = DateReminderSchedule(
        offsets: [ReminderOffset(7), ReminderOffset(7), ReminderOffset(0)],
        dailyFromDays: 2,
      );
      final restored = DateReminderSchedule.fromJson(schedule.toJson())!;
      final dates = restored.notificationTimes(
        DateTime(2026, 10, 25),
        DateTime(2026, 10, 23, 10),
      );
      expect(dates, [DateTime(2026, 10, 24, 9), DateTime(2026, 10, 25, 9)]);
      expect(
        calendarDaysBetween(DateTime(2026, 10, 26), DateTime(2026, 10, 25)),
        1,
      );
      expect(
        const DateReminderSchedule().notificationTimes(
          DateTime(2027),
          DateTime(2026),
        ),
        isEmpty,
      );
      expect(const DateReminderSchedule(dailyFromDays: 32).isValid, isFalse);
      expect(
        const DateReminderSchedule(offsets: [ReminderOffset(-1)]).isValid,
        isFalse,
      );
    },
  );

  for (final populated in [false, true]) {
    test(
      'V4 through V5 to current migration preserves ${populated ? 'representative linked records' : 'an empty database'}',
      () async {
        final dir = await Directory.systemTemp.createTemp('vehnora_v4_');
        addTearDown(() => dir.delete(recursive: true));
        final path = '${dir.path}/v4.sqlite';
        await _createV4(path, populated: populated);
        final beforeDb = await databaseFactoryFfi.openDatabase(path);
        final before = <String, List<Map<String, Object?>>>{};
        for (final table in DatabaseMigrations.requiredTablesFor(4)) {
          before[table] = await beforeDb.query(table);
        }
        await beforeDb.close();
        final database = AppDatabase(
          databaseFactory: databaseFactoryFfi,
          databasePath: path,
        );
        try {
          final db = await database.database;
          expect(
            await DatabaseMigrations.validateSchema(db),
            DatabaseMigrations.schemaVersion,
          );
          for (final table in before.keys) {
            final after = await db.query(table);
            expect(after.length, before[table]!.length);
            for (var i = 0; i < after.length; i++) {
              for (final field in before[table]![i].entries) {
                expect(
                  after[i][field.key],
                  field.value,
                  reason: '$table.${field.key} must survive migration',
                );
              }
            }
          }
          if (populated) {
            final item = (await db.query('maintenance_items')).single;
            expect(item['id'], 'oil');
            expect(item['record_kind'], 'scheduled');
            expect(item['reminder_schedule'], isNull);
            expect(item['mileage_interval'], 8000);
            expect(item['time_interval_days'], 365);
            expect(item['date_warning_days'], 21);
            expect(item['created_at'], '2026-01-01T12:00:00.000Z');
            expect(
              (await db.query('service_items')).single['maintenance_item_id'],
              'oil',
            );
            expect((await db.query('services')).single['is_baseline'], 1);
            expect(
              (await db.query('documents')).single['reminder_id'],
              'legacy-reminder',
            );
            expect(
              (await db.query('attachments')).single['stored_path'],
              'kept.pdf',
            );
            expect((await db.query('app_settings')).single['value'], 'v');
            expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
            final services = TestServices(database);
            try {
              final reminder =
                  (await services.maintenanceItemService.remindersForVehicle(
                    'v',
                    currentOdometer: 65000,
                    asOf: DateTime(2026, 2),
                  )).single;
              expect(reminder.nextMileageDue, 72000);
              expect(reminder.nextDateDue, DateTime(2027, 1, 1));
            } finally {
              await services.attachmentRoot.delete(recursive: true);
            }
          } else {
            expect(await db.query('maintenance_items'), isEmpty);
            expect(await db.query('services'), isEmpty);
          }
        } finally {
          await database.close();
        }
      },
    );
  }

  test('V4 format-1 backup restores and migrates normally', () async {
    final dir = await Directory.systemTemp.createTemp('vehnora_v4_backup_');
    addTearDown(() => dir.delete(recursive: true));
    final oldPath = '${dir.path}/v4.sqlite';
    await _createV4(oldPath, populated: false);
    final old = await databaseFactoryFfi.openDatabase(oldPath);
    await old.insert('vehicles', _vehicleMap());
    final counts = <String, int>{};
    for (final table in DatabaseMigrations.requiredTablesFor(4)) {
      counts[table] = (await old.query(table)).length;
    }
    await old.close();
    final bytes = await File(oldPath).readAsBytes();
    final manifest = BackupManifest(
      backupFormatVersion: 1,
      schemaVersion: 4,
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
    final backup = File('${dir.path}/old.dtbackup');
    await backup.writeAsBytes(ZipEncoder().encodeBytes(archive));
    final services = await createFileBackedTestServices();
    final storage = ManagedAttachmentStorage(
      rootDirectory: () async => services.attachmentRoot,
    );
    final safety = DataSafetyService(
      database: services.database,
      attachmentStorage: storage,
    );
    expect(
      (await safety.inspectBackupFile(backup.path)).manifest.schemaVersion,
      4,
    );
    await safety.restoreBackupFromFile(backup.path);
    expect(
      await (await services.database.database).getVersion(),
      DatabaseMigrations.schemaVersion,
    );
    expect(
      (await services.vehicles.listActive()).single.name,
      'Existing Fiesta',
    );
    expect(DataSafetyService.backupFormatVersion, 1);
  });

  test(
    'MOT creation needs only vehicle/name/expiry and gets the default schedule',
    () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(_draft());
      final item = await services.maintenanceItemService.createMaintenanceItem(
        _mot(vehicle.id, DateTime(2026, 10, 25)),
      );
      expect(item.mileageInterval, isNull);
      expect(item.timeIntervalDays, isNull);
      expect(
        item.reminderSchedule!.notificationTimes(
          DateTime(2026, 10, 25),
          DateTime(2026),
        ),
        hasLength(11),
      );
      final reminder = await services.maintenanceItemService.reminderForItem(
        item,
        currentOdometer: null,
        asOf: DateTime(2026, 10, 25),
      );
      expect(reminder.state, MaintenanceReminderState.due);
      expect(reminder.nextDateDue, DateTime(2026, 10, 25));
      expect(
        (await services.maintenanceItemService.reminderForItem(
          item,
          currentOdometer: null,
          asOf: DateTime(2026, 10, 26),
        )).state,
        MaintenanceReminderState.overdue,
      );
      expect(
        await services.serviceRecords.completionsForMaintenanceItem(
          vehicle.id,
          item.id,
        ),
        isEmpty,
      );
      await expectLater(
        services.serviceRecordService.createBaselineCompletion(
          item: item,
          eventDateTime: DateTime(2026),
        ),
        throwsA(isA<ValidationException>()),
      );
    },
  );

  test('multiple records get unique stable IDs; edits, archive and delete reconcile', () async {
    final services = createTestServices();
    final vehicle = await services.vehicleService.addVehicle(_draft());
    var now = DateTime(2026, 1, 1);
    final client = FakeLocalNotificationClient();
    final scheduler = _scheduler(services, client, () => now);
    final item = await services.maintenanceItemService.createMaintenanceItem(
      _mot(vehicle.id, DateTime(2026, 10, 25)),
    );
    final doc = await services.documentService.createDocument(
      VehicleDocumentDraft(
        vehicleId: vehicle.id,
        category: 'MOT',
        title: 'Certificate',
        expiryDate: DateTime(2026, 10, 25),
        reminderSchedule: const DateReminderSchedule(),
      ),
    );
    // Represent a pre-M2 duplicate: existing schedules must remain intact until
    // the user explicitly resolves them. New creation is guarded by M2.
    await (await services.database.database).update(
      'documents',
      {'reminder_schedule': DateReminderSchedule.mot.toJson()},
      where: 'id = ?',
      whereArgs: [doc.id],
    );
    final first = await scheduler.reconcile(enabled: true);
    expect(first.scheduled, hasLength(22));
    expect(first.scheduled.map((r) => r.id).toSet(), hasLength(22));
    expect(
      (await scheduler.reconcile(enabled: true)).scheduled.map((r) => r.id),
      first.scheduled.map((r) => r.id),
    );
    expect(
      first.scheduled.where((r) => r.title == 'MOT expires in 7 days'),
      hasLength(2),
    );
    final oldIds = first.scheduled
        .where((r) => r.payload == 'maintenance_date_${item.id}')
        .map((r) => r.id)
        .toSet();
    await services.maintenanceItemService.updateMaintenanceItem(
      item.id,
      _mot(
        vehicle.id,
        DateTime(2026, 12, 25),
        schedule: const DateReminderSchedule(offsets: [ReminderOffset(1)]),
      ),
    );
    final updated = await scheduler.reconcile(enabled: true);
    expect(oldIds.intersection(client.pending.keys.toSet()), isEmpty);
    expect(
      updated.scheduled
          .where((r) => r.payload == 'maintenance_date_${item.id}')
          .single
          .scheduledAt,
      DateTime(2026, 12, 24, 9),
    );
    await services.maintenanceItemService.archiveMaintenanceItem(item.id);
    await services.documentService.deleteDocumentPermanently(doc.id);
    expect((await scheduler.reconcile(enabled: true)).scheduled, isEmpty);
    expect(client.pending, isEmpty);
    now = DateTime(2027);
    expect(await scheduler.buildDateReminderRequests(), isEmpty);
  });

  test(
    'permission denial cancels OS schedules and leaves MOT status available',
    () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(_draft());
      final item = await services.maintenanceItemService.createMaintenanceItem(
        _mot(vehicle.id, DateTime(2026, 10, 25)),
      );
      final client = FakeLocalNotificationClient();
      final scheduler = _scheduler(
        services,
        client,
        () => DateTime(2026, 10, 24, 10),
      );
      expect(
        (await scheduler.reconcile(enabled: true)).scheduled,
        hasLength(1),
      );
      client.permission = LocalNotificationPermissionStatus.denied;
      expect((await scheduler.reconcile(enabled: true)).scheduled, isEmpty);
      expect(client.pending, isEmpty);
      final reminder = await services.maintenanceItemService.reminderForItem(
        item,
        currentOdometer: null,
        asOf: DateTime(2026, 10, 24),
      );
      expect(reminder.state, MaintenanceReminderState.dueSoon);
    },
  );

  test(
    'setup needed cannot displace actionable Home or overview entries',
    () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(_draft());
      await services.maintenanceItemService.createMaintenanceItem(
        MaintenanceItemDraft(
          vehicleId: vehicle.id,
          name: 'AAA no baseline',
          mileageInterval: 8000,
        ),
      );
      final mot = await services.maintenanceItemService.createMaintenanceItem(
        _mot(vehicle.id, DateTime(2026, 10, 25)),
      );
      final reminders = await services.maintenanceItemService
          .remindersForVehicle(
            vehicle.id,
            currentOdometer: 64000,
            asOf: DateTime(2026, 10, 26),
          );
      expect(reminders.first.item.id, mot.id);
      expect(reminders.last.state, MaintenanceReminderState.setupNeeded);
      expect(
        (await services.homeRepository.getVehicleDashboard(
          vehicle.id,
          now: DateTime(2026, 10, 26),
        )).nextMaintenanceAttention!.item.id,
        mot.id,
      );
      final document = await services.documentService.createDocument(
        VehicleDocumentDraft(
          vehicleId: vehicle.id,
          category: 'Insurance',
          title: 'Policy',
          expiryDate: DateTime(2026, 10, 20),
        ),
      );
      final ordered = orderReminderOverview(reminders, [
        DocumentExpiryReminder.evaluate(
          document: document,
          asOf: DateTime(2026, 10, 26),
        ),
      ]);
      expect(ordered.first.document!.document.id, document.id);
      expect(ordered.last.state, MaintenanceReminderState.setupNeeded);
      expect(
        (await services.homeRepository.getVehicleDashboard(
          vehicle.id,
          now: DateTime(2026, 10, 26),
        )).nextDocumentAttention!.document.id,
        document.id,
      );
    },
  );

  test('contextual guidance is cautious and messages use delivery day', () {
    final expired = ReminderWording.message(
      vehicle: 'Fiesta',
      name: 'MOT',
      due: DateTime(2026, 10, 25),
      asOf: DateTime(2026, 10, 26),
      expiry: true,
      mot: true,
    );
    expect(expired.title, 'MOT expired');
    expect(
      expired.body,
      allOf(contains('generally'), contains('pre-arranged')),
    );
    final due = ReminderWording.message(
      vehicle: 'Fiesta',
      name: 'MOT',
      due: DateTime(2026, 10, 25),
      asOf: DateTime(2026, 10, 25, 9),
      expiry: true,
      mot: true,
    );
    expect(due.title, 'MOT expires today');
    expect(
      ReminderWording.message(
        vehicle: 'Fiesta',
        name: 'Engine oil',
        due: DateTime(2026, 10, 25),
        asOf: DateTime(2026, 10, 26),
        expiry: false,
      ).body,
      contains('may increase engine wear'),
    );
  });

  test(
    'mechanical partial setup is explicit and actionable dates still win',
    () {
      final item = MaintenanceItem(
        id: 'oil',
        vehicleId: 'v',
        name: 'Oil',
        mileageInterval: 8000,
        timeIntervalDays: 365,
        mileageWarning: 1000,
        dateWarningDays: 30,
        reminderEnabled: true,
        isArchived: false,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final completion = MaintenanceCompletion(
        serviceId: 's',
        serviceItemId: 'si',
        maintenanceItemId: 'oil',
        itemName: 'Oil',
        eventDateTime: DateTime.utc(2026),
        odometer: null,
        totalCostMinor: 0,
        isBaseline: true,
        createdAt: DateTime.utc(2026),
      );
      const engine = MaintenanceReminderEngine();
      expect(
        engine
            .evaluate(
              item: item,
              completions: [completion],
              currentOdometer: 64000,
              asOf: DateTime(2026, 2),
            )
            .state,
        MaintenanceReminderState.setupNeeded,
      );
      expect(
        engine
            .evaluate(
              item: item,
              completions: [completion],
              currentOdometer: 64000,
              asOf: DateTime(2027, 1, 2),
            )
            .state,
        MaintenanceReminderState.overdue,
      );
    },
  );

  test('overview orders overdue, due, due soon, setup then upcoming', () {
    const engine = MaintenanceReminderEngine();
    final now = DateTime(2026, 10, 18);
    MaintenanceItem expiry(String id, DateTime? due) => MaintenanceItem(
      id: id,
      vehicleId: 'v',
      name: id,
      kind: MaintenanceRecordKind.expiry,
      expiryDate: due,
      mileageWarning: 1000,
      dateWarningDays: 30,
      reminderEnabled: true,
      isArchived: false,
      createdAt: now,
      updatedAt: now,
    );
    final reminders = [
      for (final item in [
        expiry('setup', null),
        expiry('upcoming', DateTime(2026, 11, 5)),
        expiry('soon', DateTime(2026, 10, 25)),
        expiry('due', now),
        expiry('overdue', DateTime(2026, 10, 17)),
      ])
        engine.evaluate(
          item: item,
          completions: [],
          currentOdometer: null,
          asOf: now,
        ),
    ];
    expect(orderReminderOverview(reminders, []).map((e) => e.name), [
      'overdue',
      'due',
      'soon',
      'setup',
      'upcoming',
    ]);
    expect(engine.mostUrgent(reminders)!.item.id, 'overdue');
  });

  test(
    'legacy MOT interval and new expiry can coexist without rewriting history',
    () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(_draft());
      final legacy = await services.maintenanceItemService
          .createMaintenanceItem(
            MaintenanceItemDraft(
              vehicleId: vehicle.id,
              name: 'MOT',
              timeIntervalDays: 365,
            ),
          );
      await expectLater(
        services.maintenanceItemService.createMaintenanceItem(
          _mot(vehicle.id, DateTime(2026, 10, 25)),
        ),
        throwsA(isA<ValidationException>()),
      );
      await services.maintenanceItemService.updateMaintenanceItem(
        legacy.id,
        MaintenanceItemDraft(
          vehicleId: vehicle.id,
          name: 'MOT',
          timeIntervalDays: 365,
          reminderEnabled: false,
        ),
      );
      final expiry = await services.maintenanceItemService
          .createMaintenanceItem(_mot(vehicle.id, DateTime(2026, 10, 25)));
      expect(expiry.id, isNot(legacy.id));
      expect(
        (await services.maintenanceItems.getById(legacy.id))!.kind,
        MaintenanceRecordKind.scheduled,
      );
      await expectLater(
        services.maintenanceItemService.createMaintenanceItem(
          _mot(vehicle.id, DateTime(2027)),
        ),
        throwsA(isA<ValidationException>()),
      );
      await services.maintenanceItemService.archiveMaintenanceItem(legacy.id);
      expect(
        (await services.maintenanceItems.listForVehicle(vehicle.id)).single.id,
        expiry.id,
      );
    },
  );

  testWidgets(
    'a visited Reminders screen reloads after same-vehicle mutations',
    (tester) async {
      final services = createTestServices();
      await tester.runAsync(() => services.vehicleService.addVehicle(_draft()));
      final controller = DriveTrackerController(
        database: services.database,
        clock: () => DateTime(2026, 10, 18),
      );
      addTearDown(controller.dispose);
      await tester.runAsync(controller.initialize);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: MaterialApp(
            theme: DTTheme.light(),
            home: const RemindersScreen(),
          ),
        ),
      );
      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 50 && finder.evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(finder, findsWidgets);
      }

      await waitFor(find.text('No active reminders'));
      final item = await tester.runAsync(
        () => controller.addMaintenanceItem(
          _mot(controller.selectedVehicle!.id, DateTime(2026, 10, 25)),
        ),
      );
      await tester.pump();
      await waitFor(find.byKey(Key('reminder_${item!.id}')));
      await tester.runAsync(() => controller.archiveMaintenanceItem(item.id));
      await tester.pump();
      await waitFor(find.text('No active reminders'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'MOT form hides mechanical fields on narrow large-text light and dark screens',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 760));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.binding.setSurfaceSize(null);
      });
      final services = createTestServices();
      await tester.runAsync(() => services.vehicleService.addVehicle(_draft()));
      final controller = DriveTrackerController(
        database: services.database,
        clock: () => DateTime(2026, 10, 18),
      );
      addTearDown(controller.dispose);
      await tester.runAsync(controller.initialize);
      for (final theme in [DTTheme.light(), DTTheme.dark()]) {
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: controller,
            child: MaterialApp(
              theme: theme,
              home: const MaintenanceItemFormScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final choice = find.byKey(const Key('expiryReminderChoice'));
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('maintenanceMileageIntervalField')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('maintenanceBaselineSwitch')),
          findsNothing,
        );
        final expiry = find.byKey(const Key('maintenanceExpiryDateField'));
        await tester.scrollUntilVisible(
          expiry,
          150,
          scrollable: find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(expiry, findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}

MaintenanceItemDraft _mot(
  String vehicleId,
  DateTime expiry, {
  DateReminderSchedule? schedule,
}) => MaintenanceItemDraft(
  vehicleId: vehicleId,
  name: 'MOT',
  category: 'MOT',
  kind: MaintenanceRecordKind.expiry,
  expiryDate: expiry,
  reminderSchedule: schedule,
);
VehicleDraft _draft() => const VehicleDraft(
  name: 'Fiesta',
  make: 'Ford',
  model: 'Fiesta',
  currentOdometer: 64000,
  fuelType: FuelType.petrol,
  distanceUnit: DistanceUnit.miles,
);
ReminderNotificationScheduler _scheduler(
  TestServices s,
  FakeLocalNotificationClient client,
  DateTime Function() now,
) => ReminderNotificationScheduler(
  client: client,
  vehicleRepository: s.vehicles,
  odometerRepository: s.odometers,
  maintenanceItemService: s.maintenanceItemService,
  documentRepository: s.documents,
  clock: now,
);
Map<String, Object?> _vehicleMap() => {
  'id': 'v',
  'name': 'Existing Fiesta',
  'make': 'Ford',
  'model': 'Fiesta',
  'fuel_type': 'petrol',
  'distance_unit': 'miles',
  'created_at': '2026-01-01T12:00:00.000Z',
  'updated_at': '2026-01-01T12:00:00.000Z',
};
Future<void> _createV4(String path, {required bool populated}) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 4,
      onCreate: DatabaseMigrations.createSchema,
    ),
  );
  try {
    if (!populated) return;
    const timestamp = '2026-01-01T12:00:00.000Z';
    await db.insert('vehicles', _vehicleMap());
    await db.insert('maintenance_items', {
      'id': 'oil',
      'vehicle_id': 'v',
      'name': 'Engine oil',
      'mileage_interval': 8000,
      'time_interval_days': 365,
      'date_warning_days': 21,
      'created_at': timestamp,
      'updated_at': timestamp,
    });
    await db.insert('services', {
      'id': 's',
      'vehicle_id': 'v',
      'event_datetime': timestamp,
      'odometer': 64000,
      'is_baseline': 1,
      'created_at': timestamp,
      'updated_at': timestamp,
    });
    await db.insert('service_items', {
      'id': 'si',
      'service_id': 's',
      'maintenance_item_id': 'oil',
      'item_name': 'Engine oil',
      'created_at': timestamp,
      'updated_at': timestamp,
    });
    await db.insert('documents', {
      'id': 'd',
      'vehicle_id': 'v',
      'category': 'MOT',
      'title': 'Certificate',
      'expiry_date': '2026-10-25',
      'reminder_id': 'legacy-reminder',
      'created_at': timestamp,
      'updated_at': timestamp,
    });
    await db.insert('attachments', {
      'id': 'a',
      'parent_type': 'DOCUMENT',
      'parent_id': 'd',
      'file_name': 'kept.pdf',
      'stored_path': 'kept.pdf',
      'created_at': timestamp,
      'updated_at': timestamp,
    });
    await db.insert('app_settings', {
      'key': 'selected_vehicle_id',
      'value': 'v',
      'updated_at': timestamp,
    });
  } finally {
    await db.close();
  }
}
