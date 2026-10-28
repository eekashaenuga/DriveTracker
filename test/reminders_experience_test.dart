import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/features/home/presentation/home_screen.dart';
import 'package:drivetracker/features/reminders/presentation/reminders_screen.dart';
import 'package:drivetracker/features/reminders/domain/date_reminder_schedule.dart';

import 'notification_navigation_test.dart' show waitM3, InteractionClient;

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:drivetracker/features/maintenance/domain/maintenance_item.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_reminder.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_reminder_engine.dart';
import 'package:drivetracker/features/maintenance/domain/service_record.dart';
import 'package:drivetracker/features/reminders/domain/reminder_overview.dart';
import 'package:drivetracker/features/reminders/domain/reminder_notification_scheduler.dart';
import 'package:drivetracker/features/documents/domain/vehicle_document.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:drivetracker/core/notifications/local_notification_service.dart';

import 'helpers/test_services.dart';
import 'notification_scheduler_test.dart' show FakeLocalNotificationClient;

MaintenanceItem item(String id, {String vehicle = 'v', int? interval}) =>
    MaintenanceItem(
      id: id,
      vehicleId: vehicle,
      name: id,
      timeIntervalDays: interval,
      mileageWarning: 1000,
      dateWarningDays: 30,
      reminderEnabled: true,
      isArchived: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
MaintenanceReminder reminder(
  String id, {
  MaintenanceReminderState state = MaintenanceReminderState.dueSoon,
  int? days,
  int? distance,
  String vehicle = 'v',
}) => MaintenanceReminder(
  item: item(id, vehicle: vehicle),
  state: state,
  primaryBasis: days == null
      ? MaintenanceReminderBasis.mileage
      : MaintenanceReminderBasis.date,
  completions: const [],
  daysRemaining: days,
  milesRemaining: distance,
  nextDateDue: days == null ? null : DateTime(2026, 6, 1 + days),
);

class FailingClient extends FakeLocalNotificationClient {
  bool fail = true;
  @override
  Future<void> schedule(LocalNotificationRequest r) async {
    if (fail && r.title.contains('Insurance')) throw StateError('test failure');
    await super.schedule(r);
  }
}

void main() {
  setUpAll(tzdata.initializeTimeZones);
  for (final date in [
    DateTime(2026, 6, 1),
    DateTime(2026, 3, 29),
    DateTime(2026, 10, 25),
  ]) {
    test('local calendar maintenance interval from London midnight $date', () {
      final old = tz.local;
      tz.setLocalLocation(tz.getLocation('Europe/London'));
      addTearDown(() => tz.setLocalLocation(old));
      final instant = tz.TZDateTime(
        tz.local,
        date.year,
        date.month,
        date.day,
        0,
        30,
      );
      final completion = MaintenanceCompletion(
        serviceId: 's',
        serviceItemId: 'si',
        maintenanceItemId: 'oil',
        itemName: 'Oil',
        eventDateTime: instant,
        createdAt: instant,
        isBaseline: true,
      );
      final result = const MaintenanceReminderEngine().evaluate(
        item: item('oil', interval: 30),
        completions: [completion],
        currentOdometer: null,
        asOf: instant,
      );
      final expected = DateTime(date.year, date.month, date.day + 30);
      expect(
        (
          result.nextDateDue!.year,
          result.nextDateDue!.month,
          result.nextDateDue!.day,
        ),
        (expected.year, expected.month, expected.day),
      );
    });
  }
  test('overview due today grouping is explicit', () {
    expect(
      orderReminderOverview([
        reminder('today', state: MaintenanceReminderState.due, days: 0),
      ], []).single.sectionTitle,
      'Due today / Due now',
    );
  });
  test('maintenance sorting never compares raw mileage with days', () {
    final sorted = const MaintenanceReminderEngine().sortByUrgency([
      reminder('mileage', distance: 1),
      reminder('date', days: 5),
    ]);
    expect(sorted.map((r) => r.item.id), ['date', 'mileage']);
  });
  test(
    'one schedule failure does not abort unrelated document notifications',
    () async {
      final s = createTestServices();
      final v = await s.vehicleService.addVehicle(
        const VehicleDraft(
          name: 'Car',
          make: 'Ford',
          model: 'Focus',
          fuelType: FuelType.petrol,
          distanceUnit: DistanceUnit.miles,
          currentOdometer: 1000,
        ),
      );
      for (final name in ['Insurance', 'Tax']) {
        await s.documentService.createDocument(
          VehicleDocumentDraft(
            vehicleId: v.id,
            category: name,
            title: name,
            expiryDate: DateTime(2026, 7),
          ),
        );
      }
      final client = FailingClient();
      final scheduler = ReminderNotificationScheduler(
        client: client,
        vehicleRepository: s.vehicles,
        odometerRepository: s.odometers,
        maintenanceItemService: s.maintenanceItemService,
        documentRepository: s.documents,
        clock: () => DateTime(2026, 6),
      );
      await scheduler.reconcile(enabled: true);
      expect(client.scheduled, hasLength(1));
    },
  );
  test('overview groups overdue due soon setup and future reminders once', () {
    final result = orderReminderOverview([
      reminder('normal', state: MaintenanceReminderState.normal, days: 90),
      reminder('setup', state: MaintenanceReminderState.setupNeeded),
      reminder('soon', days: 3),
      reminder('today', state: MaintenanceReminderState.due, distance: 0),
      reminder('overdue', state: MaintenanceReminderState.overdue, days: -3),
    ], []);
    expect(result.map((r) => r.sectionTitle), [
      'Overdue',
      'Due today / Due now',
      'Due soon',
      'Review / Setup needed',
      'Upcoming',
    ]);
  });
  test('dated entries sort by due date and mileage-only entries by remaining distance', () {
    final result = orderReminderOverview([
      reminder('m20', distance: 20),
      reminder('d6', days: 6),
      reminder('m2', distance: 2),
      reminder('d1', days: 1),
    ], []);
    expect(result.map((r) => r.name), ['d1', 'd6', 'm2', 'm20']);
    expect(
      orderReminderOverview(
        result.reversed.map((e) => e.maintenance!),
        [],
      ).map((r) => r.stableKey),
      result.map((r) => r.stableKey),
    );
  });
  test('MOT conflicts are grouped per vehicle and overdue conflict retains attention', () {
    MaintenanceReminder mot(
      String v,
      String id,
      MaintenanceReminderState state,
    ) => MaintenanceReminder(
      item: MaintenanceItem(
        id: id,
        vehicleId: v,
        name: 'MOT',
        category: 'MOT',
        mileageWarning: 1000,
        dateWarningDays: 30,
        reminderEnabled: true,
        isArchived: false,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
      state: state,
      primaryBasis: MaintenanceReminderBasis.date,
      completions: const [],
      nextDateDue: DateTime(2026, 6),
    );
    final result = orderReminderOverview([
      mot('a', 'a1', MaintenanceReminderState.overdue),
      mot('a', 'a2', MaintenanceReminderState.normal),
      mot('b', 'b1', MaintenanceReminderState.normal),
      mot('b', 'b2', MaintenanceReminderState.normal),
    ], []);
    expect(result, hasLength(2));
    expect(result.first.sectionTitle, 'Overdue');
    expect(result.last.sectionTitle, 'Review / Setup needed');
    expect(
      result.every(
        (e) => e.motSources.every((s) => s.vehicleId == e.vehicleId),
      ),
      isTrue,
    );
  });
  test(
    'partial synchronization recovers without changing scheduling IDs',
    () async {
      final s = createTestServices();
      final v = await s.vehicleService.addVehicle(
        const VehicleDraft(
          name: 'Car',
          make: 'Ford',
          model: 'Focus',
          fuelType: FuelType.petrol,
          distanceUnit: DistanceUnit.miles,
          currentOdometer: 1000,
        ),
      );
      for (final name in ['Insurance', 'Tax']) {
        await s.documentService.createDocument(
          VehicleDocumentDraft(
            vehicleId: v.id,
            category: name,
            title: name,
            expiryDate: DateTime(2026, 7),
          ),
        );
      }
      final client = FailingClient();
      final scheduler = ReminderNotificationScheduler(
        client: client,
        vehicleRepository: s.vehicles,
        odometerRepository: s.odometers,
        maintenanceItemService: s.maintenanceItemService,
        documentRepository: s.documents,
        clock: () => DateTime(2026, 6),
      );
      final expected = await scheduler.buildDateReminderRequests();
      final failed = await scheduler.reconcile(enabled: true);
      expect(failed.isPartial, isTrue);
      expect(failed.failures, hasLength(1));
      client.fail = false;
      final recovered = await scheduler.reconcile(enabled: true);
      expect(recovered.failures, isEmpty);
      expect(recovered.scheduled.map((r) => r.id), expected.map((r) => r.id));
      expect(client.pending, hasLength(2));
    },
  );
  test(
    'turning off notifications clears owned pending and delivered alerts only',
    () async {
      final s = createTestServices();
      final client = InteractionClient();
      final id = ReminderNotificationScheduler.notificationIdForStableId(
        'document_date_old',
      );
      client.active.addAll([id, 7]);
      client.pending[id] = null;
      final scheduler = ReminderNotificationScheduler(
        client: client,
        vehicleRepository: s.vehicles,
        odometerRepository: s.odometers,
        maintenanceItemService: s.maintenanceItemService,
        documentRepository: s.documents,
        clock: DateTime.now,
      );
      await scheduler.reconcile(enabled: false);
      expect(client.active, {7});
      expect(client.pending, isEmpty);
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'vehicle and type filters combine on narrow large-text Reminders dark=$dark',
      (t) async {
        await t.binding.setSurfaceSize(const Size(320, 800));
        t.platformDispatcher.textScaleFactorTestValue = 1.8;
        addTearDown(() {
          t.binding.setSurfaceSize(null);
          t.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final s = createTestServices();
        late String a, b;
        await t.runAsync(() async {
          a = (await s.vehicleService.addVehicle(
            const VehicleDraft(
              name: 'Vehicle A',
              make: 'Ford',
              model: 'Focus',
              fuelType: FuelType.petrol,
              distanceUnit: DistanceUnit.miles,
              currentOdometer: 1000,
            ),
          )).id;
          b = (await s.vehicleService.addVehicle(
            const VehicleDraft(
              name: 'Vehicle B',
              make: 'Honda',
              model: 'Civic',
              fuelType: FuelType.petrol,
              distanceUnit: DistanceUnit.kilometers,
              currentOdometer: 1000,
            ),
          )).id;
          await s.documentService.createDocument(
            VehicleDocumentDraft(
              vehicleId: a,
              category: 'Insurance',
              title: 'Policy A',
              expiryDate: DateTime(2027),
              reminderSchedule: DateReminderSchedule.standard,
            ),
          );
          await s.documentService.createDocument(
            VehicleDocumentDraft(
              vehicleId: b,
              category: 'Tax',
              title: 'Tax B',
              expiryDate: DateTime(2027),
              reminderSchedule: DateReminderSchedule.standard,
            ),
          );
          await s.maintenanceItemService.createMaintenanceItem(
            MaintenanceItemDraft(
              vehicleId: a,
              name: 'Oil setup',
              mileageInterval: 8000,
            ),
          );
        });
        final c = DriveTrackerController(
          database: s.database,
          clock: () => DateTime(2026, 6),
        );
        await t.runAsync(c.initialize);
        await t.pumpWidget(
          ChangeNotifierProvider<DriveTrackerController>.value(
            value: c,
            child: MaterialApp(
              theme: ThemeData(
                useMaterial3: true,
                brightness: dark ? Brightness.dark : Brightness.light,
              ),
              home: const MediaQuery(
                data: MediaQueryData(
                  size: Size(320, 800),
                  textScaler: TextScaler.linear(1.8),
                  disableAnimations: true,
                ),
                child: RemindersScreen(),
              ),
            ),
          ),
        );
        await waitM3(t, find.textContaining('Tax: Tax B'));
        final vehicle = find.byWidgetPredicate(
          (w) => w is DropdownButtonFormField<String>,
        );
        await t.ensureVisible(vehicle);
        await t.tap(vehicle);
        await t.pump(const Duration(milliseconds: 350));
        await t.tap(find.text('All active vehicles').last);
        await t.pump();
        await waitM3(t, find.textContaining('Insurance: Policy A'));
        expect(find.textContaining('Vehicle A ·'), findsWidgets);
        expect(find.textContaining('Vehicle B ·'), findsWidgets);
        expect(c.nextDocumentAttention, isNull);
        final type = find.byWidgetPredicate(
          (w) => w is DropdownButtonFormField<ReminderTypeFilter>,
        );
        await t.ensureVisible(type);
        await t.tap(type);
        await t.pump(const Duration(milliseconds: 350));
        await t.tap(find.text('Documents').last);
        await t.pump();
        expect(find.text('Oil setup'), findsNothing);
        await t.drag(
          find.byKey(const Key('remindersList')),
          const Offset(0, 1000),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(vehicle);
        await t.tap(vehicle);
        await t.pump(const Duration(milliseconds: 350));
        await t.tap(find.text('Vehicle B').last);
        await t.pump();
        await waitM3(t, find.textContaining('Tax: Tax B'));
        expect(find.textContaining('Insurance: Policy A'), findsNothing);
        await t.ensureVisible(type);
        await t.tap(type);
        await t.pump(const Duration(milliseconds: 350));
        await t.tap(find.text('Maintenance').last);
        await t.pump();
        await waitM3(t, find.text('No reminders match these filters'));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
  testWidgets(
    'All vehicles refresh safely when a vehicle with visible reminders is archived',
    (t) async {
      final s = createTestServices();
      final c = DriveTrackerController(
        database: s.database,
        clock: () => DateTime(2026, 6, 1),
      );
      late String vehicleA;
      await t.runAsync(() async {
        for (final name in ['Vehicle A', 'Vehicle B']) {
          final v = await s.vehicleService.addVehicle(
            VehicleDraft(
              name: name,
              make: 'Ford',
              model: 'Focus',
              fuelType: FuelType.petrol,
              distanceUnit: DistanceUnit.miles,
              currentOdometer: 1000,
            ),
          );
          if (name == 'Vehicle A') vehicleA = v.id;
          await s.documentService.createDocument(
            VehicleDocumentDraft(
              vehicleId: v.id,
              category: 'Insurance',
              title: 'Policy $name',
              expiryDate: DateTime(2027),
              reminderSchedule: DateReminderSchedule.standard,
            ),
          );
        }
        await c.initialize();
      });
      await t.pumpWidget(
        ChangeNotifierProvider<DriveTrackerController>.value(
          value: c,
          child: const MaterialApp(home: RemindersScreen()),
        ),
      );
      await waitM3(t, find.textContaining('Policy Vehicle B'));
      await t.tap(
        find.byWidgetPredicate((w) => w is DropdownButtonFormField<String>),
      );
      await t.pump(const Duration(milliseconds: 350));
      await t.tap(find.text('All active vehicles').last);
      await t.pump();
      await waitM3(t, find.textContaining('Policy Vehicle A'));
      await t.runAsync(() => c.archiveVehicle(vehicleA));
      await t.pump();
      expect(t.takeException(), isNull);
      await waitM3(t, find.textContaining('Policy Vehicle B'));
      expect(find.textContaining('Policy Vehicle A'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'Reminders loading failure offers retry instead of an endless spinner',
    (t) async {
      final s = createTestServices();
      await t.runAsync(
        () => s.vehicleService.addVehicle(
          const VehicleDraft(
            name: 'Car',
            make: 'Ford',
            model: 'Focus',
            fuelType: FuelType.petrol,
            distanceUnit: DistanceUnit.miles,
            currentOdometer: 1000,
          ),
        ),
      );
      final c = FailingReminderController(database: s.database);
      await t.runAsync(c.initialize);
      await t.pumpWidget(
        ChangeNotifierProvider<DriveTrackerController>.value(
          value: c,
          child: const MaterialApp(home: RemindersScreen()),
        ),
      );
      await waitM3(t, find.text('Could not load reminders'));
      c.fail = false;
      await t.ensureVisible(find.text('Retry'));
      await t.tap(find.text('Retry'));
      await waitM3(t, find.text('No active reminders'));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets('Reminders has a distinct no-vehicles state', (t) async {
    final s = createTestServices();
    final c = DriveTrackerController(database: s.database);
    await t.runAsync(c.initialize);
    await t.pumpWidget(
      ChangeNotifierProvider<DriveTrackerController>.value(
        value: c,
        child: const MaterialApp(home: RemindersScreen()),
      ),
    );
    expect(find.text('No active vehicle'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets(
    'Home Tax attention says Due and retains its short attention window',
    (t) async {
      final s = createTestServices();
      await t.runAsync(() async {
        final v = await s.vehicleService.addVehicle(
          const VehicleDraft(
            name: 'Tax car',
            make: 'Ford',
            model: 'Focus',
            fuelType: FuelType.petrol,
            distanceUnit: DistanceUnit.miles,
            currentOdometer: 1000,
          ),
        );
        await s.documentService.createDocument(
          VehicleDocumentDraft(
            vehicleId: v.id,
            category: 'Tax',
            title: 'Tax record',
            expiryDate: DateTime(2026, 6, 5),
          ),
        );
      });
      final c = DriveTrackerController(
        database: s.database,
        clock: () => DateTime(2026, 6, 1),
      );
      await t.runAsync(c.initialize);
      await t.pumpWidget(
        ChangeNotifierProvider<DriveTrackerController>.value(
          value: c,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await waitM3(t, find.textContaining('Tax: Tax record'));
      expect(find.textContaining('· Due '), findsWidgets);
      expect(find.textContaining('· Expires '), findsNothing);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}

class FailingReminderController extends DriveTrackerController {
  FailingReminderController({required super.database});
  bool fail = true;
  @override
  Future<List<MaintenanceReminder>> maintenanceRemindersForVehicle(
    String id,
  ) async {
    if (fail) throw StateError('fixture query failure');
    return super.maintenanceRemindersForVehicle(id);
  }
}
