import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/app/theme/dt_theme.dart';
import 'package:drivetracker/features/documents/domain/vehicle_document.dart';
import 'package:drivetracker/app/router/app_navigation.dart';
import 'package:drivetracker/features/reminders/domain/date_reminder_schedule.dart';
import 'package:drivetracker/features/reminders/presentation/reminders_screen.dart';
import 'package:drivetracker/features/reminders/domain/reminder_overview.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_item.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_reminder.dart';
import 'package:drivetracker/core/notifications/local_notification_service.dart';
import 'package:drivetracker/core/utilities/validation_exception.dart';
import 'package:drivetracker/shared/widgets/date_reminder_editor.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/test_services.dart';
import 'notification_scheduler_test.dart' show FakeLocalNotificationClient;

final _now = DateTime(2026, 10, 27, 8);
final _expiry = DateTime(2027, 1, 21);
const _vehicle = VehicleDraft(
  name: 'My Fiesta',
  make: 'Ford',
  model: 'Fiesta',
  fuelType: FuelType.petrol,
  distanceUnit: DistanceUnit.miles,
  currentOdometer: 70000,
);

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets);
}

Widget _app(
  DriveTrackerController controller, {
  Widget child = const RemindersScreen(),
}) => ChangeNotifierProvider.value(
  value: controller,
  child: MaterialApp(theme: DTTheme.light(), home: child),
);

Future<
  ({
    TestServices services,
    DriveTrackerController controller,
    FakeLocalNotificationClient notifications,
  })
>
_start(WidgetTester tester, {bool permissionGranted = true}) async {
  final services = createTestServices();
  await tester.runAsync(() => services.vehicleService.addVehicle(_vehicle));
  final notifications = FakeLocalNotificationClient();
  if (!permissionGranted) {
    notifications.permission = LocalNotificationPermissionStatus.denied;
  }
  final controller = DriveTrackerController(
    database: services.database,
    clock: () => _now,
    notificationClient: notifications,
  );
  addTearDown(controller.dispose);
  await tester.runAsync(controller.initialize);
  await tester.runAsync(
    () => controller.setLocalReminderNotificationsEnabled(true),
  );
  return (
    services: services,
    controller: controller,
    notifications: notifications,
  );
}

VehicleDocumentDraft _draft(
  DriveTrackerController controller, {
  String category = 'MOT',
  DateTime? expiry,
  DateReminderSchedule? schedule = DateReminderSchedule.standard,
  bool withoutExpiry = false,
}) => VehicleDocumentDraft(
  vehicleId: controller.selectedVehicle!.id,
  category: category,
  title: category == 'MOT' ? 'MOT certificate' : '$category document',
  issueDate: DateTime(2025, 12, 17),
  expiryDate: withoutExpiry ? null : expiry ?? _expiry,
  reminderSchedule: schedule,
);

Future<VehicleDocument> _add(
  WidgetTester tester,
  DriveTrackerController controller, {
  String category = 'MOT',
  DateTime? expiry,
  DateReminderSchedule? schedule = DateReminderSchedule.standard,
  bool withoutExpiry = false,
}) async => (await tester.runAsync(
  () => controller.addDocument(
    _draft(
      controller,
      category: category,
      expiry: expiry,
      schedule: schedule,
      withoutExpiry: withoutExpiry,
    ),
  ),
))!;

void main() {
  testWidgets('future document MOT appears on Reminders beyond 30 days', (
    tester,
  ) async {
    final services = createTestServices();
    await tester.runAsync(() => services.vehicleService.addVehicle(_vehicle));
    final notifications = FakeLocalNotificationClient();
    final controller = DriveTrackerController(
      database: services.database,
      clock: () => _now,
      notificationClient: notifications,
    );
    addTearDown(controller.dispose);
    await tester.runAsync(controller.initialize);
    await tester.runAsync(
      () => controller.setLocalReminderNotificationsEnabled(true),
    );
    final document = (await tester.runAsync(
      () => controller.addDocument(
        VehicleDocumentDraft(
          vehicleId: controller.selectedVehicle!.id,
          category: 'MOT',
          title: 'MOT certificate',
          issueDate: DateTime(2025, 12, 17),
          expiryDate: _expiry,
          reminderSchedule: DateReminderSchedule.mot,
        ),
      ),
    ))!;
    final stored = (await tester.runAsync(
      () => services.documents.getById(document.id),
    ))!;
    expect(stored.expiryDate, _expiry);
    expect(
      stored.reminderSchedule!.toJson(),
      DateReminderSchedule.mot.toJson(),
    );
    expect(stored.statusAt(_now), DocumentStatus.valid);
    expect(notifications.pending, isNotEmpty);
    expect(
      notifications.pending.values.every(
        (request) => request!.scheduledAt.hour == 9,
      ),
      isTrue,
    );
    await tester.pumpWidget(_app(controller));
    await _waitFor(tester, find.byKey(Key('documentReminder_${document.id}')));
    expect(find.text('My Fiesta'), findsOneWidget);
    expect(find.textContaining('21 Jan 2027'), findsWidgets);
    expect(find.text('No active reminders'), findsNothing);
  });

  for (final category in ['Insurance', 'Vehicle tax', 'Warranty']) {
    testWidgets(
      'future $category schedule appears without becoming a Home attention alert',
      (tester) async {
        final f = await _start(tester);
        final document = await _add(tester, f.controller, category: category);
        final reminders = (await tester.runAsync(
          f.controller.documentRemindersForSelectedVehicle,
        ))!;
        expect(reminders.single.document.id, document.id);
        expect(reminders.single.state, MaintenanceReminderState.normal);
        expect(reminders.single.needsAttention, isFalse);
        expect(f.controller.nextDocumentAttention, isNull);
        expect(f.notifications.pending, isNotEmpty);
        await tester.pumpWidget(_app(f.controller));
        await _waitFor(
          tester,
          find.byKey(Key('documentReminder_${document.id}')),
        );
        expect(
          find.textContaining(
            '${category == 'Vehicle tax' ? 'Due' : 'Expires'} 21 Jan 2027',
          ),
          findsWidgets,
        );
        if (category == 'Vehicle tax') {
          expect(find.textContaining('Expires'), findsNothing);
        }
        expect(find.text('Upcoming'), findsWidgets);
      },
    );
  }

  testWidgets('future MOT date stays readable on narrow large-text Reminders', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final f = await _start(tester);
    final document = await _add(tester, f.controller);
    await tester.pumpWidget(
      _app(
        f.controller,
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 800),
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: const RemindersScreen(),
        ),
      ),
    );
    final card = find.byKey(Key('documentReminder_${document.id}'));
    await _waitFor(tester, card);
    final date = find.descendant(
      of: card,
      matching: find.textContaining('Expires 21 Jan 2027'),
    );
    expect(
      tester.renderObject<RenderParagraph>(date).didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'disabled future schedules, missing dates and archived documents stay inactive',
    (tester) async {
      final f = await _start(tester);
      final disabled = await _add(
        tester,
        f.controller,
        category: 'Insurance',
        schedule: const DateReminderSchedule(),
      );
      await _add(
        tester,
        f.controller,
        category: 'Warranty',
        withoutExpiry: true,
      );
      final archived = await _add(tester, f.controller);
      await tester.runAsync(() => f.controller.archiveDocument(archived.id));
      expect(
        (await tester.runAsync(
          f.controller.documentRemindersForSelectedVehicle,
        ))!,
        isEmpty,
      );
      expect(f.notifications.pending, isEmpty);
      final stored = (await tester.runAsync(
        () => f.services.documents.getById(disabled.id),
      ))!;
      expect(stored.statusAt(_now), DocumentStatus.valid);
      await tester.pumpWidget(_app(f.controller));
      await _waitFor(tester, find.text('No active reminders'));
      expect(find.byKey(Key('documentReminder_${disabled.id}')), findsNothing);
      expect(find.byKey(Key('documentReminder_${archived.id}')), findsNothing);
    },
  );

  testWidgets(
    'legacy null schedule retains its implicit date reminder without rewriting data',
    (tester) async {
      final f = await _start(tester);
      final document = await _add(
        tester,
        f.controller,
        category: 'Insurance',
        schedule: null,
      );
      expect(
        (await tester.runAsync(
          () => f.services.documents.getById(document.id),
        ))!.reminderSchedule,
        isNull,
      );
      expect(f.notifications.pending, hasLength(1));
      await tester.pumpWidget(_app(f.controller));
      await _waitFor(
        tester,
        find.byKey(Key('documentReminder_${document.id}')),
      );
    },
  );

  testWidgets(
    'legacy MOT edit displays the stored default until recommended timings are explicitly saved',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = await _start(tester);
      final document = await _add(
        tester,
        f.controller,
        schedule: const DateReminderSchedule(),
      );
      await tester.runAsync(() async {
        await (await f.services.database.database).update(
          'documents',
          {'reminder_schedule': null},
          where: 'id = ?',
          whereArgs: [document.id],
        );
      });
      final legacy = (await tester.runAsync(
        () => f.services.documents.getById(document.id),
      ))!;
      await tester.pumpWidget(
        _app(
          f.controller,
          child: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () =>
                    AppNavigation.openEditDocument(context, legacy),
                child: const Text('Edit legacy MOT'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit legacy MOT'));
      await tester.pump();
      await _waitFor(tester, find.byKey(const Key('documentTitleField')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.scrollUntilVisible(
        find.text('30 days before'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('3 months before'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Use recommended MOT timings'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      final recommended = find.text('Use recommended MOT timings');
      await tester.ensureVisible(recommended);
      await tester.pump();
      expect(recommended.hitTestable(), findsOneWidget);
      await tester.tap(find.text('Use recommended MOT timings'));
      await tester.pump();
      expect(find.text('3 months before'), findsOneWidget);
      await tester.tap(find.byKey(const Key('saveDocumentButton')));
      await _waitFor(tester, find.byType(SnackBar));
      final saved = (await tester.runAsync(
        () => f.services.documents.getById(document.id),
      ))!;
      expect(
        saved.reminderSchedule!.toJson(),
        DateReminderSchedule.mot.toJson(),
      );
      expect(
        f.notifications.pending.values.where(
          (r) => r!.payload == 'document_date_${document.id}',
        ),
        isNotEmpty,
      );
    },
  );

  testWidgets('daily-only on-the-day schedule is enabled', (tester) async {
    final f = await _start(tester);
    final document = await _add(
      tester,
      f.controller,
      category: 'Insurance',
      schedule: const DateReminderSchedule(dailyFromDays: 0),
    );
    expect(
      f.notifications.pending.values.single!.scheduledAt,
      DateTime(2027, 1, 21, 9),
    );
    await tester.pumpWidget(_app(f.controller));
    await _waitFor(tester, find.byKey(Key('documentReminder_${document.id}')));
  });

  testWidgets(
    'disabled notifications preserve near-due and overdue attention boundaries',
    (tester) async {
      final f = await _start(tester);
      final documents = <VehicleDocument>[];
      for (final days in [-1, 0, 7, 30, 31]) {
        documents.add(
          await _add(
            tester,
            f.controller,
            category: 'Insurance',
            expiry: DateTime(_now.year, _now.month, _now.day + days),
            schedule: const DateReminderSchedule(),
          ),
        );
      }
      final reminders = (await tester.runAsync(
        f.controller.documentRemindersForSelectedVehicle,
      ))!;
      expect(reminders.map((r) => r.state), [
        MaintenanceReminderState.overdue,
        MaintenanceReminderState.due,
        MaintenanceReminderState.dueSoon,
        MaintenanceReminderState.upcoming,
      ]);
      expect(f.notifications.pending, isEmpty);
      await tester.pumpWidget(_app(f.controller));
      await _waitFor(
        tester,
        find.byKey(Key('documentReminder_${documents.first.id}')),
      );
      for (final document in documents.take(4)) {
        expect(
          find.byKey(Key('documentReminder_${document.id}')),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(Key('documentReminder_${documents.last.id}')),
        findsNothing,
      );
      expect(find.textContaining('Expired'), findsWidgets);
    },
  );

  for (final category in ['MOT', 'Vehicle tax']) {
    testWidgets(
      '$category edits refresh a visited Reminders page and ${category == 'MOT' ? 'archive' : 'delete'} cancels notifications',
      (tester) async {
        final f = await _start(tester);
        await tester.pumpWidget(_app(f.controller));
        await _waitFor(tester, find.text('No active reminders'));
        final document = await _add(tester, f.controller, category: category);
        await tester.pump();
        await _waitFor(
          tester,
          find.byKey(Key('documentReminder_${document.id}')),
        );
        final oldIds = f.notifications.pending.keys.toSet();
        await tester.runAsync(
          () => f.controller.updateDocument(
            document.id,
            _draft(
              f.controller,
              category: category,
              expiry: DateTime(2027, 2, 21),
            ),
          ),
        );
        await tester.pump();
        await _waitFor(tester, find.textContaining('21 Feb 2027'));
        expect(find.textContaining('21 Jan 2027'), findsNothing);
        expect(
          oldIds.intersection(f.notifications.pending.keys.toSet()),
          isEmpty,
        );
        final updatedIds = f.notifications.pending.keys.toSet();
        expect(updatedIds, isNotEmpty);
        if (category == 'MOT') {
          await tester.runAsync(
            () => f.controller.archiveDocument(document.id),
          );
        } else {
          await tester.runAsync(
            () => f.controller.deleteDocumentPermanently(document.id),
          );
        }
        await tester.pump();
        await _waitFor(tester, find.text('No active reminders'));
        expect(
          find.byKey(Key('documentReminder_${document.id}')),
          findsNothing,
        );
        expect(f.notifications.pending, isEmpty);
        expect(
          f.notifications.cancelled.toSet().containsAll(updatedIds),
          isTrue,
        );
      },
    );
  }

  testWidgets(
    'multiple MOT sources form one review entry with both dates and editable records',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = await _start(tester);
      final item = (await tester.runAsync(
        () => f.controller.addMaintenanceItem(
          MaintenanceItemDraft(
            vehicleId: f.controller.selectedVehicle!.id,
            name: 'MOT',
            kind: MaintenanceRecordKind.expiry,
            expiryDate: _expiry,
          ),
        ),
      ))!;
      final document = await _add(
        tester,
        f.controller,
        expiry: DateTime(2027, 2, 21),
        schedule: const DateReminderSchedule(),
      );
      // Existing pre-M2 databases can contain two enabled sources. Do not merge
      // either record or select a date when presenting that historical state.
      await tester.runAsync(() async {
        await (await f.services.database.database).update(
          'documents',
          {'reminder_schedule': DateReminderSchedule.mot.toJson()},
          where: 'id = ?',
          whereArgs: [document.id],
        );
      });
      final maintenance = (await tester.runAsync(
        f.controller.maintenanceRemindersForSelectedVehicle,
      ))!;
      final documents = (await tester.runAsync(
        f.controller.documentRemindersForSelectedVehicle,
      ))!;
      final entries = orderReminderOverview(maintenance, documents);
      expect(entries, hasLength(1));
      expect(entries.single.motSources, hasLength(2));
      expect(entries.single.days, isNull);
      await tester.runAsync(() async {
        await expectLater(
          f.controller.addDocument(_draft(f.controller)),
          throwsA(isA<ValidationException>()),
        );
      });
      await tester.pumpWidget(
        _app(
          f.controller,
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 800),
              textScaler: TextScaler.linear(1.8),
              disableAnimations: true,
            ),
            child: const RemindersScreen(),
          ),
        ),
      );
      final group = find.byKey(
        Key('motReminderSources_${f.controller.selectedVehicle!.id}'),
      );
      await _waitFor(tester, group);
      expect(find.byKey(Key('documentReminder_${document.id}')), findsNothing);
      expect(find.byKey(Key('reminder_${item.id}')), findsNothing);
      expect(find.textContaining('21 Jan 2027'), findsWidgets);
      expect(find.textContaining('21 Feb 2027'), findsWidgets);
      expect(tester.takeException(), isNull);
      final reviewTitle = find.descendant(
        of: group,
        matching: find.text('MOT - review sources'),
      );
      await tester.ensureVisible(reviewTitle);
      await tester.pump();
      expect(reviewTitle.hitTestable(), findsOneWidget);
      await tester.tap(reviewTitle);
      await tester.pump();
      await _waitFor(
        tester,
        find.byKey(Key('complianceDocument_${document.id}')),
      );
      expect(
        find.byKey(Key('complianceMaintenance_${item.id}')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'existing maintenance remains visible beside a scheduled document',
    (tester) async {
      final f = await _start(tester);
      final item = (await tester.runAsync(
        () => f.controller.addMaintenanceItem(
          MaintenanceItemDraft(
            vehicleId: f.controller.selectedVehicle!.id,
            name: 'Oil change',
            mileageInterval: 8000,
          ),
        ),
      ))!;
      final document = await _add(tester, f.controller, category: 'Insurance');
      await tester.pumpWidget(_app(f.controller));
      await _waitFor(
        tester,
        find.byKey(Key('documentReminder_${document.id}')),
      );
      expect(find.byKey(Key('reminder_${item.id}')), findsOneWidget);
    },
  );

  testWidgets(
    'configured document reminders do not depend on notification permission',
    (tester) async {
      final f = await _start(tester, permissionGranted: false);
      final document = await _add(tester, f.controller);
      expect(f.notifications.pending, isEmpty);
      await tester.pumpWidget(_app(f.controller));
      await _waitFor(
        tester,
        find.byKey(Key('documentReminder_${document.id}')),
      );
    },
  );

  testWidgets(
    'MOT timing action uses user-facing wording and restores recommended timings',
    (tester) async {
      DateReminderSchedule schedule = const DateReminderSchedule();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => DateReminderEditor(
                  value: schedule,
                  showMotPreset: true,
                  onChanged: (value) => setState(() => schedule = value),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('MOT preset'), findsNothing);
      await tester.tap(find.text('Use recommended MOT timings'));
      await tester.pump();
      expect(schedule.toJson(), DateReminderSchedule.mot.toJson());
      expect(find.text('3 months before'), findsOneWidget);
      expect(
        find.text('Daily: 7 days before through expiry/due day'),
        findsOneWidget,
      );
    },
  );
}
