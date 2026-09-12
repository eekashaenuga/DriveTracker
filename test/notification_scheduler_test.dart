import 'dart:io';

import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/core/notifications/local_notification_service.dart';
import 'package:drivetracker/features/attachments/domain/attachment_io.dart';
import 'package:drivetracker/features/data_safety/domain/data_safety_service.dart';
import 'package:drivetracker/features/documents/domain/vehicle_document.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_item.dart';
import 'package:drivetracker/features/maintenance/domain/service_record.dart';
import 'package:drivetracker/features/reminders/domain/reminder_notification_scheduler.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_services.dart';

void main() {
  group('ReminderNotificationScheduler', () {
    test(
      'schedules date maintenance reminders at the local warning time',
      () async {
        final services = createTestServices();
        final vehicle = await _addVehicle(services, name: 'Ford Fiesta');
        final item = await _addDateMaintenanceItem(services, vehicle);
        await _completeItem(
          services,
          vehicle: vehicle,
          item: item,
          eventDateTime: DateTime(2025, 10, 1, 12),
          odometer: 70000,
          isBaseline: true,
        );
        final client = FakeLocalNotificationClient();
        final scheduler = _scheduler(
          services,
          client,
          now: () => DateTime(2026, 9, 1, 8),
        );

        final result = await scheduler.reconcile(enabled: true);

        expect(result.scheduled, hasLength(1));
        final request = result.scheduled.single;
        expect(request.stableId, 'maintenance_date_${item.id}');
        expect(
          request.id,
          ReminderNotificationScheduler.notificationIdForStableId(
            request.stableId,
          ),
        );
        expect(request.scheduledAt, DateTime(2026, 9, 1, 9));
        expect(request.title, 'DriveTracker');
        expect(request.body, 'Ford Fiesta - MOT due on 1 Oct 2026');
        expect(client.pendingNotificationIds(), completion([request.id]));
      },
    );

    test(
      'updates an existing reminder schedule without changing identity',
      () async {
        final services = createTestServices();
        final vehicle = await _addVehicle(services);
        final item = await _addDateMaintenanceItem(services, vehicle);
        await _completeItem(
          services,
          vehicle: vehicle,
          item: item,
          eventDateTime: DateTime(2025, 10, 1, 12),
          odometer: 70000,
          isBaseline: true,
        );
        final client = FakeLocalNotificationClient();
        final scheduler = _scheduler(
          services,
          client,
          now: () => DateTime(2026, 9, 1, 8),
        );
        final first = (await scheduler.reconcile(enabled: true))
            .scheduled
            .single;

        final updated = await services.maintenanceItemService
            .updateMaintenanceItem(
              item.id,
              MaintenanceItemDraft(
                vehicleId: vehicle.id,
                name: item.name,
                timeIntervalDays: item.timeIntervalDays,
                dateWarningDays: 7,
              ),
            );
        client.scheduled.clear();
        client.cancelled.clear();

        final second = (await scheduler.reconcile(enabled: true))
            .scheduled
            .single;

        expect(updated.dateWarningDays, 7);
        expect(second.id, first.id);
        expect(second.stableId, first.stableId);
        expect(second.scheduledAt, DateTime(2026, 9, 24, 9));
        expect(client.cancelled, contains(first.id));
        expect(await client.pendingNotificationIds(), [first.id]);
      },
    );

    test(
      'completion cancels the obsolete schedule and schedules the next cycle',
      () async {
        final services = createTestServices();
        final vehicle = await _addVehicle(services);
        final item = await _addDateMaintenanceItem(services, vehicle);
        await _completeItem(
          services,
          vehicle: vehicle,
          item: item,
          eventDateTime: DateTime(2025, 10, 1, 12),
          odometer: 70000,
          isBaseline: true,
        );
        final client = FakeLocalNotificationClient();
        var now = DateTime(2026, 9, 1, 8);
        final scheduler = _scheduler(services, client, now: () => now);
        final oldRequest = (await scheduler.reconcile(enabled: true))
            .scheduled
            .single;

        await _completeItem(
          services,
          vehicle: vehicle,
          item: item,
          eventDateTime: DateTime(2026, 9, 10, 12),
          odometer: 71000,
        );
        now = DateTime(2026, 9, 11, 8);
        client.scheduled.clear();
        client.cancelled.clear();

        final newRequest = (await scheduler.reconcile(enabled: true))
            .scheduled
            .single;

        expect(client.cancelled, contains(oldRequest.id));
        expect(newRequest.id, oldRequest.id);
        expect(newRequest.scheduledAt, DateTime(2027, 8, 11, 9));
        expect(newRequest.body, 'Commuter - MOT due on 10 Sep 2027');
      },
    );

    test('cancels schedules when reminders become inactive', () async {
      final services = createTestServices();
      final vehicle = await _addVehicle(services);
      final item = await _addDateMaintenanceItem(services, vehicle);
      await _completeItem(
        services,
        vehicle: vehicle,
        item: item,
        eventDateTime: DateTime(2025, 10, 1, 12),
        odometer: 70000,
        isBaseline: true,
      );
      final client = FakeLocalNotificationClient();
      final scheduler = _scheduler(
        services,
        client,
        now: () => DateTime(2026, 9, 1, 8),
      );
      final request = (await scheduler.reconcile(enabled: true))
          .scheduled
          .single;

      await services.maintenanceItemService.updateMaintenanceItem(
        item.id,
        MaintenanceItemDraft(
          vehicleId: vehicle.id,
          name: item.name,
          timeIntervalDays: item.timeIntervalDays,
          reminderEnabled: false,
        ),
      );
      client.scheduled.clear();
      client.cancelled.clear();

      final result = await scheduler.reconcile(enabled: true);

      expect(result.scheduled, isEmpty);
      expect(client.cancelled, contains(request.id));
      expect(await client.pendingNotificationIds(), isEmpty);
    });

    test('schedules document reminders for multiple vehicles without sensitive '
        'titles', () async {
      final services = createTestServices();
      final fiesta = await _addVehicle(services, name: 'Ford Fiesta');
      final civic = await _addVehicle(services, name: 'Honda Civic');
      final insurance = await services.documentService.createDocument(
        VehicleDocumentDraft(
          vehicleId: fiesta.id,
          category: 'Insurance',
          title: 'Policy ABC123',
          expiryDate: DateTime(2026, 10, 1),
        ),
      );
      final mot = await services.documentService.createDocument(
        VehicleDocumentDraft(
          vehicleId: civic.id,
          category: 'MOT',
          title: 'Certificate ZX9',
          expiryDate: DateTime(2026, 10, 2),
        ),
      );
      final client = FakeLocalNotificationClient();
      final scheduler = _scheduler(
        services,
        client,
        now: () => DateTime(2026, 9, 1, 8),
      );

      final result = await scheduler.reconcile(enabled: true);

      expect(result.scheduled.map((request) => request.stableId), [
        'document_date_${insurance.id}',
        'document_date_${mot.id}',
      ]);
      expect(
        result.scheduled.first.body,
        'Ford Fiesta - Insurance expires on 1 Oct 2026',
      );
      expect(
        result.scheduled.last.body,
        'Honda Civic - MOT expires on 2 Oct 2026',
      );
      expect(result.scheduled.first.body, isNot(contains('Policy ABC123')));
      expect(result.scheduled.last.body, isNot(contains('Certificate ZX9')));
    });

    test('permission denied cancels pending notifications but leaves in-app '
        'reminders intact', () async {
      final services = createTestServices();
      final vehicle = await _addVehicle(services);
      final item = await _addDateMaintenanceItem(services, vehicle);
      await _completeItem(
        services,
        vehicle: vehicle,
        item: item,
        eventDateTime: DateTime(2025, 10, 1, 12),
        odometer: 70000,
        isBaseline: true,
      );
      final staleId = ReminderNotificationScheduler.notificationIdForStableId(
        'maintenance_date_${item.id}',
      );
      final client = FakeLocalNotificationClient()
        ..permission = LocalNotificationPermissionStatus.denied
        ..pending[staleId] = null;
      final scheduler = _scheduler(
        services,
        client,
        now: () => DateTime(2026, 9, 1, 8),
      );

      final result = await scheduler.reconcile(enabled: true);
      final inAppReminders = await services.maintenanceItemService
          .remindersForVehicle(vehicle.id, currentOdometer: 70000);

      expect(result.scheduled, isEmpty);
      expect(client.cancelled, [staleId]);
      expect(inAppReminders.single.shouldShowAsReminder, isTrue);
      expect(inAppReminders.single.nextDateDue, DateTime.utc(2026, 10, 1));
    });

    test('startup reconciliation removes stale IDs and leaves one desired schedule', () async {
      final services = createTestServices();
      final vehicle = await _addVehicle(services);
      final item = await _addDateMaintenanceItem(services, vehicle);
      await _completeItem(
        services,
        vehicle: vehicle,
        item: item,
        eventDateTime: DateTime(2025, 10, 1, 12),
        odometer: 70000,
        isBaseline: true,
      );
      final staleId = ReminderNotificationScheduler.notificationIdForStableId(
        'document_date_missing',
      );
      final client = FakeLocalNotificationClient()..pending[staleId] = null;
      final scheduler = _scheduler(
        services,
        client,
        now: () => DateTime(2026, 9, 1, 8),
      );

      final result = await scheduler.reconcile(enabled: true);

      expect(result.scheduled, hasLength(1));
      expect(client.cancelled, [staleId]);
      expect(await client.pendingNotificationIds(), [
        result.scheduled.single.id,
      ]);
    });

    test(
      'does not create duplicate pending schedules for existing reminders',
      () async {
        final services = createTestServices();
        final vehicle = await _addVehicle(services);
        final item = await _addDateMaintenanceItem(services, vehicle);
        await _completeItem(
          services,
          vehicle: vehicle,
          item: item,
          eventDateTime: DateTime(2025, 10, 1, 12),
          odometer: 70000,
          isBaseline: true,
        );
        final client = FakeLocalNotificationClient();
        final scheduler = _scheduler(
          services,
          client,
          now: () => DateTime(2026, 9, 1, 8),
        );
        final existing = (await scheduler.buildDateReminderRequests()).single;
        client.pending[existing.id] = existing;

        final result = await scheduler.reconcile(enabled: true);

        expect(result.scheduled, hasLength(1));
        expect(client.cancelled, [existing.id]);
        expect(await client.pendingNotificationIds(), [existing.id]);
      },
    );

    test('ignores archived vehicles and inactive reminder records', () async {
      final services = createTestServices();
      final vehicle = await _addVehicle(services);
      final item = await _addDateMaintenanceItem(services, vehicle);
      await _completeItem(
        services,
        vehicle: vehicle,
        item: item,
        eventDateTime: DateTime(2025, 10, 1, 12),
        odometer: 70000,
        isBaseline: true,
      );
      final client = FakeLocalNotificationClient();
      final scheduler = _scheduler(
        services,
        client,
        now: () => DateTime(2026, 9, 1, 8),
      );
      final request = (await scheduler.reconcile(enabled: true))
          .scheduled
          .single;

      await services.vehicleService.archiveVehicle(vehicle.id);
      client.scheduled.clear();
      client.cancelled.clear();

      final result = await scheduler.reconcile(enabled: true);

      expect(result.scheduled, isEmpty);
      expect(client.cancelled, [request.id]);
      expect(await client.pendingNotificationIds(), isEmpty);
    });

    test(
      'mileage reminders are not scheduled as background notifications',
      () async {
        final services = createTestServices();
        final vehicle = await _addVehicle(services);
        final item = await services.maintenanceItemService
            .createMaintenanceItem(
              MaintenanceItemDraft(
                vehicleId: vehicle.id,
                name: 'Tyres',
                mileageInterval: 10000,
                mileageWarning: 1000,
              ),
            );
        await _completeItem(
          services,
          vehicle: vehicle,
          item: item,
          eventDateTime: DateTime(2026, 1, 1, 12),
          odometer: 60000,
          isBaseline: true,
        );
        final client = FakeLocalNotificationClient();
        final scheduler = _scheduler(
          services,
          client,
          now: () => DateTime(2026, 9, 1, 8),
        );

        final result = await scheduler.reconcile(enabled: true);
        final reminders = await services.maintenanceItemService
            .remindersForVehicle(vehicle.id, currentOdometer: 70000);

        expect(result.scheduled, isEmpty);
        expect(reminders.single.shouldShowAsReminder, isTrue);
        expect(reminders.single.nextMileageDue, 70000);
        expect(reminders.single.nextDateDue, isNull);
      },
    );
  });

  group('DriveTrackerController notifications', () {
    test('startup reconciles stored notification preference', () async {
      final services = createTestServices();
      final vehicle = await _addVehicle(services);
      final item = await _addDateMaintenanceItem(services, vehicle);
      await _completeItem(
        services,
        vehicle: vehicle,
        item: item,
        eventDateTime: DateTime(2025, 10, 1, 12),
        odometer: 70000,
        isBaseline: true,
      );
      await services.settings.setLocalReminderNotificationsEnabled(true);
      final client = FakeLocalNotificationClient();
      final controller = DriveTrackerController(
        database: services.database,
        notificationClient: client,
        clock: () => DateTime(2026, 9, 1, 8),
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.localReminderNotificationsEnabled, isTrue);
      expect(client.scheduled, hasLength(1));
      expect(client.scheduled.single.stableId, 'maintenance_date_${item.id}');
    });

    test('permission denial does not enable notification preference', () async {
      final services = createTestServices();
      final client = FakeLocalNotificationClient()
        ..permission = LocalNotificationPermissionStatus.denied;
      final controller = DriveTrackerController(
        database: services.database,
        notificationClient: client,
        clock: () => DateTime(2026, 9, 1, 8),
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.setLocalReminderNotificationsEnabled(true);

      expect(controller.localReminderNotificationsEnabled, isFalse);
      expect(
        controller.localNotificationPermissionStatus,
        LocalNotificationPermissionStatus.denied,
      );
      expect(
        await services.settings.getLocalReminderNotificationsEnabled(),
        isFalse,
      );
      expect(client.scheduled, isEmpty);
    });

    test('restore reloads preference and reconciles schedules', () async {
      final source = await createFileBackedTestServices();
      final vehicle = await _addVehicle(source, name: 'Restored Fiesta');
      final item = await _addDateMaintenanceItem(source, vehicle);
      await _completeItem(
        source,
        vehicle: vehicle,
        item: item,
        eventDateTime: DateTime(2025, 10, 1, 12),
        odometer: 70000,
        isBaseline: true,
      );
      await source.settings.setLocalReminderNotificationsEnabled(true);
      final backupOutput = await Directory.systemTemp.createTemp(
        'dt_notification_restore_',
      );
      addTearDown(() async {
        if (await backupOutput.exists()) {
          await backupOutput.delete(recursive: true);
        }
      });
      final backup = await DataSafetyService(
        database: source.database,
        attachmentStorage: _storage(source),
        clock: () => DateTime.utc(2026, 1, 1, 12),
      ).createBackup(outputDirectory: backupOutput);
      final target = await createFileBackedTestServices();
      final client = FakeLocalNotificationClient();
      final controller = DriveTrackerController(
        database: target.database,
        attachmentStorage: _storage(target),
        dataSafetyFileBridge: FakeDataSafetyFileBridge(),
        notificationClient: client,
        clock: () => DateTime(2026, 9, 1, 8),
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      expect(controller.localReminderNotificationsEnabled, isFalse);

      await controller.restoreBackupFromFile(
        backup.file.path,
        fileName: backup.suggestedName,
      );

      expect(controller.localReminderNotificationsEnabled, isTrue);
      expect(controller.selectedVehicle?.name, 'Restored Fiesta');
      expect(client.scheduled, hasLength(1));
      expect(client.scheduled.single.stableId, 'maintenance_date_${item.id}');
      expect(
        client.scheduled.single.body,
        'Restored Fiesta - MOT due on 1 Oct 2026',
      );
    });
  });
}

ReminderNotificationScheduler _scheduler(
  TestServices services,
  FakeLocalNotificationClient client, {
  required DateTime Function() now,
}) {
  return ReminderNotificationScheduler(
    client: client,
    vehicleRepository: services.vehicles,
    odometerRepository: services.odometers,
    maintenanceItemService: services.maintenanceItemService,
    documentRepository: services.documents,
    clock: now,
  );
}

Future<Vehicle> _addVehicle(TestServices services, {String name = 'Commuter'}) {
  return services.vehicleService.addVehicle(
    VehicleDraft(
      name: name,
      make: 'Ford',
      model: 'Focus',
      currentOdometer: 70000,
      fuelType: FuelType.petrol,
      distanceUnit: DistanceUnit.miles,
    ),
  );
}

Future<MaintenanceItem> _addDateMaintenanceItem(
  TestServices services,
  Vehicle vehicle,
) {
  return services.maintenanceItemService.createMaintenanceItem(
    MaintenanceItemDraft(
      vehicleId: vehicle.id,
      name: 'MOT',
      timeIntervalDays: 365,
      dateWarningDays: 30,
    ),
  );
}

Future<void> _completeItem(
  TestServices services, {
  required Vehicle vehicle,
  required MaintenanceItem item,
  required DateTime eventDateTime,
  int? odometer,
  bool isBaseline = false,
}) async {
  if (isBaseline) {
    await services.serviceRecordService.createBaselineCompletion(
      item: item,
      eventDateTime: eventDateTime,
      odometer: odometer,
    );
    return;
  }
  await services.serviceRecordService.createServiceRecord(
    ServiceRecordDraft(
      vehicleId: vehicle.id,
      eventDateTime: eventDateTime,
      odometer: odometer,
      totalCostMinor: 0,
      items: [
        ServiceItemDraft(maintenanceItemId: item.id, itemName: item.name),
      ],
    ),
    allowHistorical: true,
    confirmLargeIncrease: true,
  );
}

ManagedAttachmentStorage _storage(TestServices services) {
  return ManagedAttachmentStorage(
    rootDirectory: () async => services.attachmentRoot,
  );
}

class FakeDataSafetyFileBridge implements DataSafetyFileBridge {
  @override
  Future<PickedBackupFile?> pickBackupFile() async => null;

  @override
  Future<DataSafetyFileSaveResult> saveFile({
    required String sourcePath,
    required String suggestedName,
    required String mimeType,
  }) async {
    return const DataSafetyFileSaveResult(DataSafetyFileSaveStatus.saved);
  }
}

class FakeLocalNotificationClient implements LocalNotificationClient {
  LocalNotificationPermissionStatus permission =
      LocalNotificationPermissionStatus.granted;
  final pending = <int, LocalNotificationRequest?>{};
  final scheduled = <LocalNotificationRequest>[];
  final cancelled = <int>[];
  var initializeCount = 0;

  @override
  bool get isSupported => true;

  @override
  Future<void> initialize() async {
    initializeCount += 1;
  }

  @override
  Future<LocalNotificationPermissionStatus> permissionStatus() async {
    return permission;
  }

  @override
  Future<LocalNotificationPermissionStatus> requestPermission() async {
    return permission;
  }

  @override
  Future<List<int>> pendingNotificationIds() async {
    return pending.keys.toList()..sort();
  }

  @override
  Future<void> schedule(LocalNotificationRequest request) async {
    scheduled.add(request);
    pending[request.id] = request;
  }

  @override
  Future<void> cancel(int id) async {
    if (pending.containsKey(id)) {
      cancelled.add(id);
      pending.remove(id);
    }
  }
}
