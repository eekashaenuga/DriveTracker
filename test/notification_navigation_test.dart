import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drivetracker/app/app.dart';
import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/app/router/reminder_notification_router.dart';
import 'package:drivetracker/features/maintenance/presentation/service_form_screen.dart';
import 'package:drivetracker/app/router/app_navigation.dart';
import 'package:drivetracker/core/notifications/local_notification_service.dart';
import 'package:drivetracker/core/notifications/notification_target.dart';
import 'package:drivetracker/features/documents/domain/vehicle_document.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_item.dart';
import 'package:drivetracker/features/reminders/presentation/reminders_screen.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';

import 'helpers/test_services.dart';
import 'notification_scheduler_test.dart' show FakeLocalNotificationClient;

class InteractionClient extends FakeLocalNotificationClient
    implements NotificationInteractionClient {
  @override
  void Function(NotificationTarget)? onNotificationTap;
  NotificationTarget? initial;
  bool failInitialization = false;
  @override
  Future<void> initialize() async {
    if (failInitialization) throw StateError('initialization unavailable');
    await super.initialize();
  }

  String zone = 'Europe/London';
  @override
  String? timezoneWarning;
  int refreshes = 0, permissionChecks = 0;
  Completer<void>? refreshBlocker;
  final active = <int>{};
  @override
  Future<NotificationTarget?> launchTarget() async => initial;
  @override
  Future<String?> refreshTimezone() async {
    refreshes++;
    await refreshBlocker?.future;
    return zone;
  }

  @override
  Future<bool> openNotificationSettings() async => true;
  @override
  Future<List<int>> activeNotificationIds() async => active.toList();
  @override
  Future<void> cancel(int id) async {
    active.remove(id);
    await super.cancel(id);
  }

  @override
  Future<LocalNotificationPermissionStatus> permissionStatus() async {
    permissionChecks++;
    return super.permissionStatus();
  }

  void emit(NotificationTarget target) => onNotificationTap?.call(target);
}

const car = VehicleDraft(
  name: 'Vehicle A',
  make: 'Ford',
  model: 'Focus',
  fuelType: FuelType.petrol,
  distanceUnit: DistanceUnit.miles,
  currentOdometer: 1000,
);
Future<void> waitM3(WidgetTester t, Finder f) async {
  for (var i = 0; i < 200; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 50));
    if (f.evaluate().isNotEmpty) return;
  }
  expect(f, findsWidgets);
}

void main() {
  test(
    'typed and legacy payloads parse without splitting source record IDs',
    () {
      expect(
        NotificationTarget.parse('document_date_doc_a_b')!.recordId,
        'doc_a_b',
      );
      expect(
        NotificationTarget.parse('maintenance_date_maint_a_b')!.source,
        NotificationSource.maintenance,
      );
      expect(
        NotificationTarget.parse('{"v":1,"source":"document","id":"doc_a"}')!
            .recordId,
        'doc_a',
      );
      for (final value in [
        null,
        '',
        'bad',
        'document_date_',
        'document_date_../../x',
        '{"v":2,"id":"x"}',
        '{"v":1,"source":"document","id":3}',
      ]) {
        expect(NotificationTarget.parse(value), isNull);
      }
    },
  );
  test('router queues before readiness, deduplicates callbacks and accepts a later tap', () async {
    var now = DateTime(2026);
    final router = ReminderNotificationRouter(clock: () => now);
    const target = NotificationTarget(NotificationSource.document, 'doc_1');
    final opened = <NotificationTarget>[];
    router.enqueue(target);
    router.enqueue(target);
    await router.drain(ready: false, open: (t) async => opened.add(t));
    expect(opened, isEmpty);
    expect(router.pendingCount, 1);
    await router.drain(ready: true, open: (t) async => opened.add(t));
    expect(opened, hasLength(1));
    now = now.add(const Duration(seconds: 3));
    router.enqueue(target);
    await router.drain(ready: true, open: (t) async => opened.add(t));
    expect(opened, hasLength(2));
  });
  for (final cold in [true, false]) {
    testWidgets(
      '${cold ? 'cold' : 'warm'} document tap opens its Details over correctly scoped Reminders',
      (t) async {
        final s = createTestServices();
        late VehicleDocument doc;
        await t.runAsync(() async {
          final v = await s.vehicleService.addVehicle(car);
          doc = await s.documentService.createDocument(
            VehicleDocumentDraft(
              vehicleId: v.id,
              category: 'Insurance',
              title: 'Target policy',
              expiryDate: DateTime(2027),
            ),
          );
          await s.vehicleService.addVehicle(
            const VehicleDraft(
              name: 'Vehicle B',
              make: 'Honda',
              model: 'Civic',
              fuelType: FuelType.petrol,
              distanceUnit: DistanceUnit.kilometers,
              currentOdometer: 1000,
            ),
          );
        });
        final client = InteractionClient();
        final target = NotificationTarget(NotificationSource.document, doc.id);
        if (cold) client.initial = target;
        final c = DriveTrackerController(
          database: s.database,
          notificationClient: client,
          clock: () => DateTime(2026, 6),
        );
        await t.pumpWidget(
          DriveTrackerApp(database: s.database, controller: c),
        );
        if (!cold) {
          await waitM3(t, find.text('Home'));
          client.emit(target);
          client.emit(target);
        }
        await waitM3(t, find.byKey(const Key('documentDetailsLoaded')));
        expect(find.text('Target policy'), findsWidgets);
        expect(
          find.byType(RemindersScreen, skipOffstage: false),
          findsOneWidget,
        );
        await t.pageBack();
        await waitM3(t, find.byType(RemindersScreen));
        await waitM3(t, find.byKey(Key('documentReminder_${doc.id}')));
        expect(find.text('Vehicle A'), findsWidgets);
        expect(c.selectedVehicle!.name, 'Vehicle B');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'target emitted before bootstrap is queued; maintenance tap opens source details',
    (t) async {
      final s = createTestServices();
      late MaintenanceItem maintenance;
      await t.runAsync(() async {
        final v = await s.vehicleService.addVehicle(car);
        maintenance = await s.maintenanceItemService.createMaintenanceItem(
          MaintenanceItemDraft(
            vehicleId: v.id,
            name: 'Oil target',
            mileageInterval: 8000,
          ),
        );
      });
      final client = InteractionClient();
      final c = DriveTrackerController(
        database: s.database,
        notificationClient: client,
      );
      client.emit(
        NotificationTarget(NotificationSource.maintenance, maintenance.id),
      );
      await t.pumpWidget(DriveTrackerApp(database: s.database, controller: c));
      await waitM3(
        t,
        find.byKey(const Key('maintenanceDetailRecordServiceButton')),
      );
      expect(find.text('Oil target'), findsWidgets);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Record service resolves the source vehicle without changing Home selection',
    (t) async {
      final s = createTestServices();
      late MaintenanceItem maintenance;
      await t.runAsync(() async {
        final a = await s.vehicleService.addVehicle(car);
        maintenance = await s.maintenanceItemService.createMaintenanceItem(
          MaintenanceItemDraft(
            vehicleId: a.id,
            name: 'Oil',
            mileageInterval: 8000,
          ),
        );
        await s.vehicleService.addVehicle(
          const VehicleDraft(
            name: 'Vehicle B',
            make: 'Honda',
            model: 'Civic',
            fuelType: FuelType.petrol,
            distanceUnit: DistanceUnit.miles,
            currentOdometer: 5000,
          ),
        );
      });
      final c = DriveTrackerController(
        database: s.database,
        notificationClient: InteractionClient(),
      );
      await t.pumpWidget(DriveTrackerApp(database: s.database, controller: c));
      await waitM3(t, find.text('Home'));
      final context = t.element(find.text('Home').first);
      unawaited(
        AppNavigation.openService(
          context,
          preselectedMaintenanceItemId: maintenance.id,
        ),
      );
      await waitM3(t, find.byType(ServiceFormScreen));
      final form = t.widget<ServiceFormScreen>(find.byType(ServiceFormScreen));
      expect(form.initialVehicleId, maintenance.vehicleId);
      expect(form.initialOdometer, 1000);
      expect(c.selectedVehicle!.name, 'Vehicle B');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  test('resolver safely rejects deleted/archived sources and vehicles; MOT conflict routes to review', () async {
    final s = createTestServices();
    final v = await s.vehicleService.addVehicle(car);
    final client = InteractionClient();
    final c = DriveTrackerController(
      database: s.database,
      notificationClient: client,
    );
    await c.initialize();
    addTearDown(c.dispose);
    final doc = await c.addDocument(
      VehicleDocumentDraft(
        vehicleId: v.id,
        category: 'MOT',
        title: 'MOT',
        expiryDate: DateTime(2027),
      ),
    );
    final legacy = MaintenanceItem(
      id: 'legacy',
      vehicleId: v.id,
      name: 'MOT',
      category: 'MOT',
      kind: MaintenanceRecordKind.expiry,
      expiryDate: DateTime(2027),
      mileageWarning: 1000,
      dateWarningDays: 30,
      reminderEnabled: true,
      isArchived: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await s.maintenanceItems.insert(legacy);
    final target = NotificationTarget(NotificationSource.document, doc.id);
    expect((await resolveReminderNotification(c, target)).review, isTrue);
    await c.archiveDocument(doc.id);
    expect((await resolveReminderNotification(c, target)).target, isNull);
    await c.deleteDocumentPermanently(doc.id);
    expect((await resolveReminderNotification(c, target)).message, isNotNull);
    await c.archiveVehicle(v.id);
    expect(
      (await resolveReminderNotification(
        c,
        const NotificationTarget(NotificationSource.maintenance, 'legacy'),
      )).target,
      isNull,
    );
    expect(
      (await resolveReminderNotification(
        c,
        const NotificationTarget(NotificationSource.document, 'missing'),
      )).message,
      isNotNull,
    );
  });
  test('resume environment rechecks permission/timezone, advances day and coalesces concurrent refresh', () async {
    final s = createTestServices();
    await s.vehicleService.addVehicle(car);
    final client = InteractionClient();
    var now = DateTime(2026, 6, 1, 23, 59);
    final c = DriveTrackerController(
      database: s.database,
      notificationClient: client,
      clock: () => now,
    );
    await c.initialize();
    addTearDown(c.dispose);
    await c.setLocalReminderNotificationsEnabled(false);
    final before = c.dataRevision;
    now = DateTime(2026, 6, 2, 9);
    client.zone = 'Asia/Tokyo';
    client.permission = LocalNotificationPermissionStatus.denied;
    client.refreshBlocker = Completer<void>();
    final a = c.refreshReminderEnvironment(force: true);
    final b = c.refreshReminderEnvironment(force: true);
    expect(identical(a, b), isTrue);
    client.refreshBlocker!.complete();
    await a;
    expect(c.dataRevision, greaterThan(before));
    expect(c.reminderTimezone, 'Asia/Tokyo');
    expect(
      c.localNotificationPermissionStatus,
      LocalNotificationPermissionStatus.denied,
    );
    expect(c.localReminderNotificationsPreferred, isFalse);
    client.permission = LocalNotificationPermissionStatus.granted;
    await c.refreshReminderEnvironment(force: true);
    expect(c.localReminderNotificationsEnabled, isFalse);
    expect(client.scheduled, isEmpty);
  });
  test('notification health distinguishes off, denied, partial, unavailable and retry recovery', () async {
    final s = createTestServices();
    await s.vehicleService.addVehicle(car);
    final client = InteractionClient();
    final c = DriveTrackerController(
      database: s.database,
      notificationClient: client,
    );
    await c.initialize();
    addTearDown(c.dispose);
    await c.setLocalReminderNotificationsEnabled(false);
    expect(c.notificationHealthLabel, contains('off'));
    client.permission = LocalNotificationPermissionStatus.denied;
    await c.refreshReminderEnvironment(force: true);
    expect(c.notificationHealthLabel, contains('denied'));
    client.permission = LocalNotificationPermissionStatus.granted;
    await c.setLocalReminderNotificationsEnabled(true);
    c.notificationFailureCount = 1;
    expect(c.notificationHealthLabel, contains('Some notifications'));
    client.failInitialization = true;
    await c.refreshReminderEnvironment(force: true);
    expect(c.notificationSyncError, isNotNull);
    expect(c.notificationHealthLabel, contains('failed'));
    expect(c.localReminderNotificationsPreferred, isTrue);
    client.failInitialization = false;
    await c.refreshReminderEnvironment(force: true);
    expect(c.notificationSyncError, isNull);
    expect(c.notificationFailureCount, 0);
    expect(c.notificationHealthLabel, contains('09:00'));
    expect(await c.openAndroidNotificationSettings(), isTrue);
  });
  testWidgets(
    'only an actual background/resume refreshes; trivial inactive events do not',
    (t) async {
      final s = createTestServices();
      await t.runAsync(() => s.vehicleService.addVehicle(car));
      final client = InteractionClient();
      final c = DriveTrackerController(
        database: s.database,
        notificationClient: client,
      );
      await t.pumpWidget(DriveTrackerApp(database: s.database, controller: c));
      await waitM3(t, find.text('Home'));
      final before = client.refreshes;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(client.refreshes, before);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 20; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await t.pump();
      }
      expect(client.refreshes, greaterThan(before));
      await t.pumpWidget(const SizedBox());
    },
  );
}
