import 'package:drivetracker/app/app.dart';
import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/app/theme/dt_theme.dart';
import 'package:drivetracker/features/attachments/domain/attachment_io.dart';
import 'package:drivetracker/features/settings/presentation/vehicle_units_screen.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:drivetracker/shared/widgets/dt_activity_row.dart';
import 'package:drivetracker/shared/widgets/dt_list_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/test_services.dart';

void main() {
  testWidgets(
    'Home polish tolerates narrow dark layout and long vehicle names',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final services = createTestServices();
      await tester.runAsync(() async {
        await services.vehicleService.addVehicle(
          _vehicleDraft(
            'Very Long Family Estate With Roof Box And Weekend Kit',
          ),
        );
      });

      await _pumpApp(
        tester,
        services,
        find.byKey(const Key('homeDashboardList')),
        themeMode: ThemeMode.dark,
      );

      expect(find.byKey(const Key('selectedVehicleButton')), findsOneWidget);
      expect(find.byKey(const Key('homeOdometerPanel')), findsOneWidget);
      expect(find.byKey(const Key('homeMonthSpendMetric')), findsOneWidget);
      expect(find.byKey(const Key('homeFuelPriceMetric')), findsOneWidget);
      expect(find.byKey(const Key('homeFuelEconomyMetric')), findsOneWidget);
      expect(find.text('No fuel data'), findsOneWidget);
      expect(find.text('Not enough data'), findsOneWidget);
      await _scrollUntilFound(
        tester,
        find.byKey(const Key('homeRecentActivityList')),
      );
      expect(find.byKey(const Key('homeRecentActivityList')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Quick entry sheet uses a narrow two-column grid', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final services = createTestServices();
    await tester.runAsync(() async {
      await services.vehicleService.addVehicle(_vehicleDraft('Commuter'));
    });

    await _pumpApp(
      tester,
      services,
      find.byKey(const Key('mainActionButton')),
      themeMode: ThemeMode.dark,
    );
    await _tapAndPump(tester, find.byKey(const Key('mainActionButton')));
    await _pumpUntilFound(tester, find.byKey(const Key('actionRefuelTile')));

    expect(find.byKey(const Key('actionRefuelTile')), findsOneWidget);
    expect(find.byKey(const Key('actionServiceTile')), findsOneWidget);
    expect(find.byKey(const Key('actionExpenseTile')), findsOneWidget);
    expect(find.byKey(const Key('actionIncomeTile')), findsOneWidget);
    expect(find.byKey(const Key('actionOdometerTile')), findsOneWidget);
    expect(find.byKey(const Key('actionMaintenanceTile')), findsOneWidget);

    final refuelTop = tester.getTopLeft(
      find.byKey(const Key('actionRefuelTile')),
    );
    final serviceTop = tester.getTopLeft(
      find.byKey(const Key('actionServiceTile')),
    );
    expect((refuelTop.dy - serviceTop.dy).abs(), lessThan(1));
    expect(serviceTop.dx, greaterThan(refuelTop.dx));

    final maintenanceTile = find.byKey(const Key('actionMaintenanceTile'));
    await tester.ensureVisible(maintenanceTile);
    await tester.pump();
    await _tapAndPump(tester, maintenanceTile);
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('maintenanceNameField')),
    );

    expect(find.byKey(const Key('maintenanceNameField')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'More polish keeps grouped destinations reachable on narrow dark',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final services = createTestServices();
      await tester.runAsync(() async {
        await services.vehicleService.addVehicle(_vehicleDraft('Commuter'));
      });

      await _pumpApp(
        tester,
        services,
        find.byKey(const Key('mainActionButton')),
        themeMode: ThemeMode.dark,
      );
      await _tapAndPump(tester, find.text('More').last);
      await _pumpUntilFound(tester, find.text('More'));

      expect(find.text('Vehicle'), findsWidgets);
      expect(find.text('Records'), findsOneWidget);
      await _scrollUntilFound(
        tester,
        find.byKey(const Key('moreMaintenanceTile')),
      );
      expect(find.byKey(const Key('moreMaintenanceTile')), findsOneWidget);
      expect(find.byKey(const Key('moreDocumentsTile')), findsOneWidget);
      await _scrollUntilFound(
        tester,
        find.byKey(const Key('moreFuelCalculatorTile')),
      );
      expect(find.text('Tools'), findsOneWidget);
      expect(find.byKey(const Key('moreFuelCalculatorTile')), findsOneWidget);
      await _scrollUntilFound(
        tester,
        find.byKey(const Key('moreDataStorageTile')),
      );
      expect(find.text('Data & Storage'), findsOneWidget);
      expect(find.byKey(const Key('moreDataStorageTile')), findsOneWidget);
      await _scrollUntilFound(tester, find.text('Preferences'));
      expect(find.text('Preferences'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('List cards keep trailing chevrons anchored on phone widths', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final width in [320.0, 360.0, 412.0]) {
      for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
        await tester.binding.setSurfaceSize(Size(width, 420));
        await tester.pumpWidget(
          MaterialApp(
            theme: DTTheme.light(),
            darkTheme: DTTheme.dark(),
            themeMode: themeMode,
            home: Scaffold(
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: DTListCard(
                    key: const Key('listCardAlignmentSubject'),
                    icon: Icons.history_rounded,
                    title: 'History records with an intentionally long destination title',
                    subtitle: 'Fuel, expense, income, service and odometer records with a long subtitle',
                    accentColor: Colors.blue,
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      key: Key('listCardTrailingChevron'),
                    ),
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final cardRight = tester
            .getTopRight(find.byKey(const Key('listCardAlignmentSubject')))
            .dx;
        final chevronRight = tester
            .getTopRight(find.byKey(const Key('listCardTrailingChevron')))
            .dx;
        expect(chevronRight, lessThanOrEqualTo(cardRight));
        expect(chevronRight, greaterThan(width - 72));
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('Activity rows align amounts and tolerate long text', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final width in [320.0, 360.0, 412.0]) {
      await tester.binding.setSurfaceSize(Size(width, 520));
      await tester.pumpWidget(
        MaterialApp(
          theme: DTTheme.light(),
          home: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: const [
                    DTActivityRow(
                      icon: Icons.payments_outlined,
                      title: 'Very long airport parking category with extra detail',
                      subtitle:
                          'Airport Long Stay / 2026-09-03 08:00 / 123,456 mi',
                      trailing: Text('£10.00', key: Key('smallHistoryAmount')),
                      accentColor: Colors.red,
                    ),
                    DTActivityRow(
                      icon: Icons.work_outline_rounded,
                      title: 'Very long income source that should not push amount away',
                      subtitle: 'Mileage reclaim with a long descriptive secondary line',
                      trailing: Text(
                        '£1,234,567.89',
                        key: Key('largeHistoryAmount'),
                      ),
                      accentColor: Colors.green,
                    ),
                    DTActivityRow(
                      icon: Icons.speed_rounded,
                      title: 'Manual odometer entry with a very long explanatory title',
                      subtitle:
                          '2026-09-05 09:30 / 124,000 mi / no monetary amount',
                      accentColor: Colors.blue,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final smallRight = tester
          .getTopRight(find.byKey(const Key('smallHistoryAmount')))
          .dx;
      final largeRight = tester
          .getTopRight(find.byKey(const Key('largeHistoryAmount')))
          .dx;
      expect((smallRight - largeRight).abs(), lessThan(1));
      expect(largeRight, greaterThan(width - 156));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Vehicle unit settings tolerate long names on phone widths', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final services = createTestServices();
    await tester.runAsync(() async {
      await services.vehicleService.addVehicle(
        _vehicleDraft(
          'Very Long Family Estate With Business Use And Weekend Kit',
        ),
      );
    });

    final controller = DriveTrackerController(
      database: services.database,
      clock: () => DateTime.utc(2026, 9, 20, 12),
      attachmentStorage: ManagedAttachmentStorage(
        rootDirectory: () async => services.attachmentRoot,
      ),
      attachmentPicker: services.attachmentPicker,
      attachmentOpener: services.attachmentOpener,
    );
    addTearDown(controller.dispose);
    await tester.runAsync(controller.initialize);

    for (final width in [320.0, 360.0, 412.0]) {
      for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
        await tester.binding.setSurfaceSize(Size(width, 640));
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: controller,
            child: MaterialApp(
              theme: DTTheme.light(),
              darkTheme: DTTheme.dark(),
              themeMode: themeMode,
              home: const VehicleUnitsScreen(),
            ),
          ),
        );
        await _pumpUntilFound(
          tester,
          find.byKey(const Key('vehicleUnitsScreen')),
        );

        expect(find.text('Vehicle units'), findsOneWidget);
        expect(find.textContaining('Very Long Family Estate'), findsOneWidget);
        expect(find.textContaining('Current: Miles (mi)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
  });
}

Future<DriveTrackerController> _pumpApp(
  WidgetTester tester,
  TestServices services,
  Finder readyFinder, {
  ThemeMode? themeMode,
}) async {
  final controller = DriveTrackerController(
    database: services.database,
    clock: () => DateTime.utc(2026, 9, 20, 12),
    attachmentStorage: ManagedAttachmentStorage(
      rootDirectory: () async => services.attachmentRoot,
    ),
    attachmentPicker: services.attachmentPicker,
    attachmentOpener: services.attachmentOpener,
  );
  await tester.runAsync(controller.initialize);
  if (themeMode != null) {
    await tester.runAsync(() => controller.setThemeMode(themeMode));
  }
  await tester.pumpWidget(
    DriveTrackerApp(database: services.database, controller: controller),
  );
  await _pumpUntilFound(tester, readyFinder);
  return controller;
}

Future<void> _tapAndPump(WidgetTester tester, Finder finder) async {
  final target = await _pumpUntilHittable(tester, finder);
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30; attempt += 1) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
}

Future<void> _scrollUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30; attempt += 1) {
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder);
      await tester.pump();
      return;
    }
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -220));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
}

Future<Finder> _pumpUntilHittable(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30; attempt += 1) {
    final hittable = finder.hitTestable();
    if (hittable.evaluate().isNotEmpty) {
      return hittable;
    }
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder);
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder.hitTestable(), findsWidgets);
  return finder.hitTestable();
}

VehicleDraft _vehicleDraft(String name) {
  return VehicleDraft(
    name: name,
    make: 'Ford',
    model: 'Focus',
    currentOdometer: 64000,
    fuelType: FuelType.petrol,
    distanceUnit: DistanceUnit.miles,
  );
}
