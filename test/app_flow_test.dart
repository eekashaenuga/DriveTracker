import 'package:drivetracker/app/app.dart';
import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/features/daily_records/domain/daily_activity.dart';
import 'package:drivetracker/features/daily_records/domain/record_category.dart';
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

    await tester.ensureVisible(
      find.byKey(const Key('homeUpdateOdometerButton')),
    );
    await tester.pump();
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

  testWidgets('central action opens Daily Records actions', (tester) async {
    final services = createTestServices();
    await tester.runAsync(() async {
      await services.vehicleService.addVehicle(_draft('Commuter', 64000));
    });

    await _pumpApp(tester, services, find.byKey(const Key('mainActionButton')));

    await _openActionSheet(tester);

    expect(find.byKey(const Key('actionRefuelTile')), findsOneWidget);
    expect(find.byKey(const Key('actionExpenseTile')), findsOneWidget);
    expect(find.byKey(const Key('actionIncomeTile')), findsOneWidget);
    expect(find.text('Odometer'), findsWidgets);
  });

  testWidgets('Refuel form can save a valid record', (tester) async {
    final services = createTestServices();
    await tester.runAsync(() async {
      await services.vehicleService.addVehicle(_draft('Commuter', 64000));
    });

    final controller = await _pumpApp(
      tester,
      services,
      find.byKey(const Key('mainActionButton')),
    );

    await _openActionForm(
      tester,
      actionKey: const Key('actionRefuelTile'),
      readyKey: const Key('refuelTotalCostField'),
    );

    await tester.enterText(find.byKey(const Key('refuelTotalCostField')), '50');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('refuelVolumeField')), '40');
    await tester.pump();
    await _scrollUntilFound(
      tester,
      find.byKey(const Key('refuelUnitPriceField')),
    );
    final unitPriceField = tester.widget<TextFormField>(
      find.byKey(const Key('refuelUnitPriceField')),
    );

    expect(unitPriceField.controller?.text, '125');
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is InputDecorator && widget.decoration.suffixText == 'p/L',
      ),
      findsOneWidget,
    );

    await _tapAndRunAsync(tester, find.byKey(const Key('saveRefuelButton')));
    await _pumpUntilFound(tester, find.text('Home'));

    final activities = await tester.runAsync<List<DailyActivity>>(
      () =>
          controller.historyForSelectedVehicle(type: DailyActivityType.refuel),
    );
    expect(activities, isNotNull);
    final savedActivities =
        activities ?? fail('Expected saved refuel activity.');
    expect(savedActivities, hasLength(1));
    expect(savedActivities.single.amountMinor, 5000);
  });

  testWidgets('Expense and Income forms save and appear in History', (
    tester,
  ) async {
    final services = createTestServices();
    await tester.runAsync(() async {
      await services.vehicleService.addVehicle(_draft('Commuter', 64000));
    });

    final controller = await _pumpApp(
      tester,
      services,
      find.byKey(const Key('mainActionButton')),
    );

    await _openActionForm(
      tester,
      actionKey: const Key('actionExpenseTile'),
      readyKey: const Key('expenseAmountField'),
    );
    await _selectDropdownItem(
      tester,
      field: find.byKey(const Key('expenseCategoryField')),
      label: 'Insurance',
    );
    await tester.enterText(find.byKey(const Key('expenseAmountField')), '12');
    await _tapAndRunAsync(tester, find.byKey(const Key('saveExpenseButton')));
    await _pumpUntilFound(tester, find.text('Home'));

    await _openActionForm(
      tester,
      actionKey: const Key('actionIncomeTile'),
      readyKey: const Key('incomeAmountField'),
    );
    await _selectDropdownItem(
      tester,
      field: find.byKey(const Key('incomeCategoryField')),
      label: 'Rideshare',
    );
    await tester.enterText(find.byKey(const Key('incomeAmountField')), '45');
    await _tapAndRunAsync(tester, find.byKey(const Key('saveIncomeButton')));
    await _pumpUntilFound(tester, find.text('Home'));

    final activities = await tester.runAsync<List<DailyActivity>>(
      () => controller.historyForSelectedVehicle(),
    );
    expect(activities, isNotNull);
    final savedActivities =
        activities ?? fail('Expected saved expense and income activity.');
    expect(
      savedActivities.map((activity) => activity.type),
      containsAll([DailyActivityType.expense, DailyActivityType.income]),
    );

    await _tapAndPump(tester, find.text('More').last);
    await _pumpUntilFound(tester, find.text('History'));
    await _tapAndPump(tester, find.text('History').first);
    await _pumpUntilFound(tester, find.text('£45.00'));

    expect(find.text('£12.00'), findsWidgets);
    expect(find.text('£45.00'), findsWidgets);
  });

  testWidgets('Expense Add Category cancel keeps form usable', (tester) async {
    final services = createTestServices();
    await tester.runAsync(() async {
      await services.vehicleService.addVehicle(_draft('Commuter', 64000));
    });

    await _pumpApp(tester, services, find.byKey(const Key('mainActionButton')));
    final beforeCategories = await _categoryNames(
      tester,
      services,
      RecordCategoryType.expense,
    );

    await _openActionForm(
      tester,
      actionKey: const Key('actionExpenseTile'),
      readyKey: const Key('expenseAmountField'),
    );
    await _openCategoryDialog(tester, title: 'New expense category');
    await _tapAndPump(tester, find.byKey(const Key('cancelCategoryButton')));
    await _pumpUntilGone(tester, find.text('New expense category'));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('expenseAmountField')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('expenseAmountField')), '12');
    await _tapAndRunAsync(tester, find.byKey(const Key('saveExpenseButton')));
    await _pumpUntilFound(tester, find.text('Home'));
    expect(tester.takeException(), isNull);

    final afterCategories = await _categoryNames(
      tester,
      services,
      RecordCategoryType.expense,
    );
    expect(afterCategories, orderedEquals(beforeCategories));
  });

  testWidgets('Expense Add Category saves an expense category', (tester) async {
    final services = createTestServices();
    await tester.runAsync(() async {
      await services.vehicleService.addVehicle(_draft('Commuter', 64000));
    });

    await _pumpApp(tester, services, find.byKey(const Key('mainActionButton')));
    final beforeExpenseCategories = await _categoryNames(
      tester,
      services,
      RecordCategoryType.expense,
    );

    await _openActionForm(
      tester,
      actionKey: const Key('actionExpenseTile'),
      readyKey: const Key('expenseAmountField'),
    );
    await _openCategoryDialog(tester, title: 'New expense category');
    await tester.enterText(
      find.byKey(const Key('categoryNameField')),
      '  Warranty Cover  ',
    );
    await _tapAndPump(tester, find.byKey(const Key('addCategoryButton')));
    await _pumpUntilGone(tester, find.text('New expense category'));
    await _pumpUntilFound(tester, find.text('Warranty Cover'));

    expect(tester.takeException(), isNull);
    expect(find.text('Warranty Cover'), findsWidgets);

    final expenseCategories = await _categoryNames(
      tester,
      services,
      RecordCategoryType.expense,
    );
    final incomeCategories = await _categoryNames(
      tester,
      services,
      RecordCategoryType.income,
    );
    expect(expenseCategories.length, beforeExpenseCategories.length + 1);
    expect(expenseCategories.where((name) => name == 'Warranty Cover'), [
      'Warranty Cover',
    ]);
    expect(incomeCategories, isNot(contains('Warranty Cover')));

    await tester.enterText(find.byKey(const Key('expenseAmountField')), '12');
    await _tapAndRunAsync(tester, find.byKey(const Key('saveExpenseButton')));
    await _pumpUntilFound(tester, find.text('Home'));

    expect(tester.takeException(), isNull);
  });

  testWidgets('Income Add Category cancel keeps form usable', (tester) async {
    final services = createTestServices();
    await tester.runAsync(() async {
      await services.vehicleService.addVehicle(_draft('Commuter', 64000));
    });

    await _pumpApp(tester, services, find.byKey(const Key('mainActionButton')));
    final beforeCategories = await _categoryNames(
      tester,
      services,
      RecordCategoryType.income,
    );

    await _openActionForm(
      tester,
      actionKey: const Key('actionIncomeTile'),
      readyKey: const Key('incomeAmountField'),
    );
    await _openCategoryDialog(tester, title: 'New income category');
    await _tapAndPump(tester, find.byKey(const Key('cancelCategoryButton')));
    await _pumpUntilGone(tester, find.text('New income category'));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('incomeAmountField')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('incomeAmountField')), '45');
    await _tapAndRunAsync(tester, find.byKey(const Key('saveIncomeButton')));
    await _pumpUntilFound(tester, find.text('Home'));
    expect(tester.takeException(), isNull);

    final afterCategories = await _categoryNames(
      tester,
      services,
      RecordCategoryType.income,
    );
    expect(afterCategories, orderedEquals(beforeCategories));
  });

  testWidgets('Income Add Category saves an income category', (tester) async {
    final services = createTestServices();
    await tester.runAsync(() async {
      await services.vehicleService.addVehicle(_draft('Commuter', 64000));
    });

    await _pumpApp(tester, services, find.byKey(const Key('mainActionButton')));
    final beforeIncomeCategories = await _categoryNames(
      tester,
      services,
      RecordCategoryType.income,
    );

    await _openActionForm(
      tester,
      actionKey: const Key('actionIncomeTile'),
      readyKey: const Key('incomeAmountField'),
    );
    await _openCategoryDialog(tester, title: 'New income category');
    await tester.enterText(
      find.byKey(const Key('categoryNameField')),
      '  Airport Runs  ',
    );
    await _tapAndPump(tester, find.byKey(const Key('addCategoryButton')));
    await _pumpUntilGone(tester, find.text('New income category'));
    await _pumpUntilFound(tester, find.text('Airport Runs'));

    expect(tester.takeException(), isNull);
    expect(find.text('Airport Runs'), findsWidgets);

    final expenseCategories = await _categoryNames(
      tester,
      services,
      RecordCategoryType.expense,
    );
    final incomeCategories = await _categoryNames(
      tester,
      services,
      RecordCategoryType.income,
    );
    expect(incomeCategories.length, beforeIncomeCategories.length + 1);
    expect(incomeCategories.where((name) => name == 'Airport Runs'), [
      'Airport Runs',
    ]);
    expect(expenseCategories, isNot(contains('Airport Runs')));

    await tester.enterText(find.byKey(const Key('incomeAmountField')), '45');
    await _tapAndRunAsync(tester, find.byKey(const Key('saveIncomeButton')));
    await _pumpUntilFound(tester, find.text('Home'));

    expect(tester.takeException(), isNull);
  });

  testWidgets('Add Category dialog validates blank and duplicate names', (
    tester,
  ) async {
    final services = createTestServices();
    await tester.runAsync(() async {
      await services.vehicleService.addVehicle(_draft('Commuter', 64000));
    });

    await _pumpApp(tester, services, find.byKey(const Key('mainActionButton')));
    await _openActionForm(
      tester,
      actionKey: const Key('actionExpenseTile'),
      readyKey: const Key('expenseAmountField'),
    );
    await _openCategoryDialog(tester, title: 'New expense category');

    await _tapAndPump(tester, find.byKey(const Key('addCategoryButton')));
    expect(find.text('Category name is required.'), findsOneWidget);
    expect(find.text('New expense category'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('categoryNameField')), '   ');
    await _tapAndPump(tester, find.byKey(const Key('addCategoryButton')));
    expect(find.text('Category name is required.'), findsOneWidget);
    expect(find.text('New expense category'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('categoryNameField')),
      'insurance',
    );
    await _tapAndPump(tester, find.byKey(const Key('addCategoryButton')));
    expect(
      find.text('A category named "insurance" already exists.'),
      findsOneWidget,
    );
    expect(find.text('New expense category'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

Future<void> _openActionSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('mainActionButton')));
  await tester.pumpAndSettle();
  await _pumpUntilFound(tester, find.byKey(const Key('actionRefuelTile')));
}

Future<void> _openActionForm(
  WidgetTester tester, {
  required Key actionKey,
  required Key readyKey,
}) async {
  await _openActionSheet(tester);
  await tester.tap(find.byKey(actionKey));
  await tester.pump();
  await _pumpUntilFound(tester, find.byKey(readyKey));
}

Future<void> _selectDropdownItem(
  WidgetTester tester, {
  required Finder field,
  required String label,
}) async {
  await _pumpUntilFound(tester, field);
  await tester.ensureVisible(field);
  await tester.pump();
  await tester.tap(field);
  await tester.pumpAndSettle();
  expect(find.text(label), findsWidgets);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _openCategoryDialog(
  WidgetTester tester, {
  required String title,
}) async {
  await _pumpUntilFound(tester, find.byTooltip('Add category'));
  await tester.tap(find.byTooltip('Add category'));
  await tester.pump();
  await _pumpUntilFound(tester, find.text(title));
}

Future<void> _scrollUntilFound(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final formScrollable = find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(finder, 240, scrollable: formScrollable);
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pump();
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
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  expect(finder, findsWidgets);
}

Future<void> _pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  int attempts = 50,
}) async {
  for (var index = 0; index < attempts; index += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isEmpty) {
      return;
    }
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    if (finder.evaluate().isEmpty) {
      return;
    }
  }
  expect(finder, findsNothing);
}

Future<List<String>> _categoryNames(
  WidgetTester tester,
  TestServices services,
  RecordCategoryType type,
) async {
  final categories = await tester.runAsync<List<RecordCategory>>(
    () => services.categories.listByType(type),
  );
  return (categories ?? fail('Expected ${type.label} categories.'))
      .map((category) => category.name)
      .toList();
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
