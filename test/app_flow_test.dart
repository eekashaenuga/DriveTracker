import 'package:drivetracker/app/app.dart';
import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_services.dart';

void main() {
  testWidgets('no vehicle shows onboarding', (tester) async {
    final services = createTestServices();

    await _pumpApp(
      tester,
      services,
      find.byKey(const Key('addFirstVehicleButton')),
    );

    expect(find.text('DriveTracker'), findsOneWidget);
    expect(find.byKey(const Key('addFirstVehicleButton')), findsOneWidget);
  });

  testWidgets('add vehicle from onboarding opens Home', (tester) async {
    final services = createTestServices();

    await _pumpApp(
      tester,
      services,
      find.byKey(const Key('addFirstVehicleButton')),
    );

    await _tapAndPump(tester, find.byKey(const Key('addFirstVehicleButton')));
    await _enterVehicle(tester, odometer: '64000');
    await _tapAndRunAsync(tester, find.byKey(const Key('saveVehicleButton')));
    await _pumpUntilFound(tester, find.text('Home'));

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Commuter'), findsWidgets);
    expect(find.text('64,000 mi'), findsWidgets);
  });

  testWidgets('switching vehicle updates Home immediately', (tester) async {
    final services = createTestServices();
    await tester.runAsync(() async {
      await services.vehicleService.addVehicle(_draft('Commuter', 1000));
      await services.vehicleService.addVehicle(_draft('Weekend', 25000));
    });

    await _pumpApp(
      tester,
      services,
      find.byKey(const Key('selectedVehicleButton')),
    );

    expect(find.text('Weekend'), findsWidgets);
    await _tapAndPump(tester, find.byKey(const Key('selectedVehicleButton')));
    await _pumpUntilFound(tester, find.text('Select vehicle'));
    await _tapAndRunAsync(tester, find.text('Commuter').last);
    await _pumpUntilFound(tester, find.text('1,000 mi'));

    expect(find.text('Commuter'), findsWidgets);
    expect(find.text('1,000 mi'), findsWidgets);
  });

  testWidgets('update odometer flow refreshes Home', (tester) async {
    final services = createTestServices();
    await tester.runAsync(() async {
      await services.vehicleService.addVehicle(_draft('Commuter', 64000));
    });

    await _pumpApp(
      tester,
      services,
      find.byKey(const Key('homeUpdateOdometerButton')),
    );

    await _tapAndPump(
      tester,
      find.byKey(const Key('homeUpdateOdometerButton')),
    );
    await _pumpUntilFound(tester, find.byKey(const Key('updateOdometerField')));
    await tester.enterText(
      find.byKey(const Key('updateOdometerField')),
      '65142',
    );
    await _tapAndRunAsync(tester, find.byKey(const Key('saveOdometerButton')));
    await _pumpUntilFound(tester, find.text('Home'));

    expect(find.text('Home'), findsWidgets);
    expect(find.text('65,142 mi'), findsWidgets);
  });
}

Future<DriveTrackerController> _pumpApp(
  WidgetTester tester,
  TestServices services,
  Finder readyFinder,
) async {
  final controller = DriveTrackerController(database: services.database);
  await tester.runAsync(controller.initialize);
  await tester.pumpWidget(
    DriveTrackerApp(database: services.database, controller: controller),
  );
  await _pumpUntilFound(tester, readyFinder);
  return controller;
}

Future<void> _enterVehicle(
  WidgetTester tester, {
  required String odometer,
}) async {
  await tester.enterText(find.byKey(const Key('vehicleNameField')), 'Commuter');
  await tester.enterText(find.byKey(const Key('vehicleMakeField')), 'Ford');
  await tester.enterText(find.byKey(const Key('vehicleModelField')), 'Focus');
  await tester.enterText(
    find.byKey(const Key('vehicleOdometerField')),
    odometer,
  );
}

Future<void> _tapAndPump(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _tapAndRunAsync(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
  await tester.pump();
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
  }
  expect(finder, findsWidgets);
}

VehicleDraft _draft(String name, int odometer) {
  return VehicleDraft(
    name: name,
    make: 'Ford',
    model: 'Focus',
    currentOdometer: odometer,
    fuelType: FuelType.petrol,
    distanceUnit: DistanceUnit.miles,
  );
}
