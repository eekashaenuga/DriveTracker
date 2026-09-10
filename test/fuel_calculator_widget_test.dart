import 'package:drivetracker/app/app.dart';
import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/features/attachments/domain/attachment_io.dart';
import 'package:drivetracker/features/daily_records/domain/refuel.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_services.dart';

void main() {
  testWidgets('More opens Fuel Calculator and manual Trip Cost calculates', (
    tester,
  ) async {
    final services = createTestServices();
    await tester.runAsync(() async {
      await services.vehicleService.addVehicle(_vehicleDraft('Commuter', 1000));
    });

    await _openFuelCalculator(tester, services);
    await _enterText(tester, const Key('tripDistanceField'), '100');
    await _enterText(tester, const Key('tripEconomyField'), '40');
    await _enterText(tester, const Key('tripFuelPriceField'), '1.45');

    expect(find.text('Fuel Calculator'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('tripEstimatedCostValue')),
        matching: find.text('£16.48'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('tripFuelRequiredValue')),
        matching: find.text('11.37 L'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('all Fuel Calculator tools are reachable and calculate results', (
    tester,
  ) async {
    final services = createTestServices();
    await tester.runAsync(() async {
      await services.vehicleService.addVehicle(_vehicleDraft('Commuter', 1000));
    });

    await _openFuelCalculator(tester, services);
    await _enterText(tester, const Key('tripDistanceField'), '100');
    await _enterText(tester, const Key('tripEconomyField'), '40');
    await _enterText(tester, const Key('tripFuelPriceField'), '1.45');

    await _tapMode(tester, 'Cost Sharing');
    await _enterText(tester, const Key('sharePeopleField'), '3');
    expect(
      find.descendant(
        of: find.byKey(const Key('costSharingPerPersonValue')),
        matching: find.text('£5.49'),
      ),
      findsOneWidget,
    );

    await _tapMode(tester, 'Fuel Required');
    expect(
      find.descendant(
        of: find.byKey(const Key('fuelRequiredValue')),
        matching: find.text('11.37 L'),
      ),
      findsOneWidget,
    );

    await _tapMode(tester, 'Price Comparison');
    await _enterText(tester, const Key('comparisonFuelAmountField'), '50');
    await _enterText(tester, const Key('comparisonStationAPriceField'), '1.45');
    await _enterText(tester, const Key('comparisonStationBPriceField'), '1.40');
    await _enterText(tester, const Key('comparisonExtraDistanceField'), '10');
    await _enterText(tester, const Key('comparisonEconomyField'), '40');

    expect(
      find.descendant(
        of: find.byKey(const Key('priceComparisonBetterOptionValue')),
        matching: find.text('Station B'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('priceComparisonGrossSavingValue')),
        matching: find.text('£2.50'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('priceComparisonNetSavingValue')),
        matching: find.text('£0.91'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('vehicle defaults populate trusted economy and latest price', (
    tester,
  ) async {
    final services = createTestServices();
    await tester.runAsync(() async {
      final vehicle = await services.vehicleService.addVehicle(
        _vehicleDraft('Commuter', 1000),
      );
      await services.refuelService.createRefuel(
        _refuelDraft(
          vehicle.id,
          odometer: 1000,
          eventDateTime: DateTime.utc(2026, 9, 1, 8),
        ),
      );
      await services.refuelService.createRefuel(
        _refuelDraft(
          vehicle.id,
          odometer: 1400,
          eventDateTime: DateTime.utc(2026, 9, 10, 8),
        ),
      );
    });

    await _openFuelCalculator(tester, services);
    await _tapKey(
      tester,
      const Key('fuelCalculatorApplyVehicleDefaultsButton'),
    );
    await _enterText(tester, const Key('tripDistanceField'), '100');

    expect(find.text('45.46'), findsWidgets);
    expect(find.text('1.250'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const Key('tripEstimatedCostValue')),
        matching: find.text('£12.50'),
      ),
      findsOneWidget,
    );

    await _enterText(tester, const Key('tripEconomyField'), '50');
    expect(find.text('Based on manual values'), findsWidgets);
  });

  testWidgets(
    'manual calculator remains usable without reliable vehicle economy',
    (tester) async {
      final services = createTestServices();
      await tester.runAsync(() async {
        final vehicle = await services.vehicleService.addVehicle(
          _vehicleDraft('Commuter', 1000),
        );
        await services.refuelService.createRefuel(
          _refuelDraft(
            vehicle.id,
            odometer: 1000,
            eventDateTime: DateTime.utc(2026, 9, 1, 8),
          ),
        );
        await services.refuelService.createRefuel(
          _refuelDraft(
            vehicle.id,
            odometer: 1400,
            eventDateTime: DateTime.utc(2026, 9, 10, 8),
            missedPreviousRefuel: true,
          ),
        );
      });

      await _openFuelCalculator(tester, services);

      expect(
        find.textContaining('No reliable fuel economy is available'),
        findsOneWidget,
      );
      await _enterText(tester, const Key('tripDistanceField'), '100');
      await _enterText(tester, const Key('tripEconomyField'), '40');
      await _enterText(tester, const Key('tripFuelPriceField'), '1.25');

      expect(
        find.descendant(
          of: find.byKey(const Key('tripEstimatedCostValue')),
          matching: find.text('£14.21'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Fuel Calculator tolerates narrow dark layout and long vehicle names',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final services = createTestServices();
      await tester.runAsync(() async {
        await services.vehicleService.addVehicle(
          _vehicleDraft(
            'Very Long Family Estate With Roof Box And Weekend Kit',
            1000,
          ),
        );
      });

      await _openFuelCalculator(tester, services, themeMode: ThemeMode.dark);
      await _enterText(tester, const Key('tripDistanceField'), '0');

      expect(find.byKey(const Key('fuelCalculatorScreen')), findsOneWidget);
      expect(
        find.text(
          'Complete distance, economy and fuel price to estimate a trip.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Future<DriveTrackerController> _pumpApp(
  WidgetTester tester,
  TestServices services,
  Finder readyFinder, {
  ThemeMode? themeMode,
}) async {
  final controller = DriveTrackerController(
    database: services.database,
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

Future<void> _openFuelCalculator(
  WidgetTester tester,
  TestServices services, {
  ThemeMode? themeMode,
}) async {
  await _pumpApp(
    tester,
    services,
    find.byKey(const Key('mainActionButton')),
    themeMode: themeMode,
  );
  await _tapText(tester, 'More');
  await _scrollUntilFound(
    tester,
    find.byKey(const Key('moreFuelCalculatorTile')),
  );
  await _tapKey(tester, const Key('moreFuelCalculatorTile'));
  await _pumpUntilFound(tester, find.byKey(const Key('fuelCalculatorScreen')));
}

Future<void> _enterText(WidgetTester tester, Key key, String value) async {
  final finder = find.byKey(key);
  await _pumpUntilFound(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.enterText(finder, value);
  await tester.pump();
}

Future<void> _tapKey(WidgetTester tester, Key key) {
  return _tapAndPump(tester, find.byKey(key));
}

Future<void> _tapText(WidgetTester tester, String text) {
  return _tapAndPump(tester, find.text(text).last);
}

Future<void> _tapMode(WidgetTester tester, String text) async {
  final finder = find.text(text).last;
  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.drag(
      find.byKey(const Key('fuelCalculatorModeSelector')),
      const Offset(-360, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
  await _tapAndPump(tester, finder);
}

Future<void> _tapAndPump(WidgetTester tester, Finder finder) async {
  final target = await _pumpUntilHittable(tester, finder);
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _scrollUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30; attempt += 1) {
    if (finder.hitTestable().evaluate().isNotEmpty) {
      return;
    }
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder);
      await tester.pump();
      if (finder.hitTestable().evaluate().isNotEmpty) {
        return;
      }
    }
    final scrollable = find.byType(ListView).hitTestable();
    expect(scrollable, findsOneWidget);
    await tester.drag(scrollable, const Offset(0, -240));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets);
}

Future<Finder> _pumpUntilHittable(
  WidgetTester tester,
  Finder finder, {
  int attempts = 50,
}) async {
  for (var index = 0; index < attempts; index += 1) {
    final hittable = finder.hitTestable();
    if (hittable.evaluate().isNotEmpty) {
      return hittable;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(finder.hitTestable(), findsWidgets);
  return finder.hitTestable();
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 50,
}) async {
  for (var index = 0; index < attempts; index += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  expect(finder, findsWidgets);
}

VehicleDraft _vehicleDraft(String name, int odometer) {
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
  required DateTime eventDateTime,
  int totalCostMinor = 5000,
  int volumeMillilitres = 40000,
  int unitPriceMicrosPerLitre = 1250000,
  bool isFullTank = true,
  bool missedPreviousRefuel = false,
}) {
  return RefuelDraft(
    vehicleId: vehicleId,
    eventDateTime: eventDateTime,
    odometer: odometer,
    fuelType: FuelType.petrol,
    totalCostMinor: totalCostMinor,
    volumeMillilitres: volumeMillilitres,
    unitPriceMicrosPerLitre: unitPriceMicrosPerLitre,
    isFullTank: isFullTank,
    missedPreviousRefuel: missedPreviousRefuel,
  );
}
