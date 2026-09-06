import 'package:drivetracker/app/app.dart';
import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/features/daily_records/domain/daily_activity.dart';
import 'package:drivetracker/features/daily_records/domain/record_category.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_item.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_reminder.dart';
import 'package:drivetracker/features/maintenance/domain/service_record.dart';
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
    expect(find.byKey(const Key('actionServiceTile')), findsOneWidget);
    expect(find.text('Odometer'), findsWidgets);
  });

  testWidgets('Maintenance items can be created, edited and archived', (
    tester,
  ) async {
    final services = createTestServices();
    late Vehicle vehicle;
    await tester.runAsync(() async {
      vehicle = await services.vehicleService.addVehicle(
        _draft('Commuter', 65000),
      );
    });

    await _pumpApp(tester, services, find.byKey(const Key('mainActionButton')));
    await _openMaintenanceScreen(tester);

    await _tapAndPump(tester, find.byKey(const Key('maintenanceAddButton')));
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('maintenanceNameField')),
    );
    await tester.enterText(
      find.byKey(const Key('maintenanceNameField')),
      'Engine Oil',
    );
    await tester.enterText(
      find.byKey(const Key('maintenanceCategoryField')),
      'Fluids',
    );
    await tester.enterText(
      find.byKey(const Key('maintenanceMileageIntervalField')),
      '8000',
    );
    await tester.enterText(
      find.byKey(const Key('maintenanceTimeIntervalField')),
      '365',
    );
    await _tapAndRunAsync(
      tester,
      find.byKey(const Key('saveMaintenanceItemButton')),
    );
    final items = await tester.runAsync<List<MaintenanceItem>>(
      () => services.maintenanceItems.listForVehicle(vehicle.id),
    );
    final savedItems = items ?? fail('Expected saved maintenance item.');
    expect(savedItems, hasLength(1));
    final item = savedItems.single;
    expect(item.name, 'Engine Oil');
    expect(item.category, 'Fluids');
    expect(item.mileageInterval, 8000);
    expect(item.timeIntervalDays, 365);

    final itemRow = find.byKey(Key('maintenanceItem_${item.id}'));
    await _pumpUntilFound(tester, itemRow);
    await _tapAndPump(tester, itemRow);
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('editMaintenanceItemButton')),
    );
    await _tapAndPump(
      tester,
      find.byKey(const Key('editMaintenanceItemButton')),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('maintenanceNameField')),
    );
    await tester.enterText(
      find.byKey(const Key('maintenanceNameField')),
      'Engine Oil Plus',
    );
    await tester.enterText(
      find.byKey(const Key('maintenanceMileageIntervalField')),
      '9000',
    );
    await _tapAndRunAsync(
      tester,
      find.byKey(const Key('saveMaintenanceItemButton')),
    );
    await _pumpUntilFound(tester, find.text('Engine Oil Plus'));
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('archiveMaintenanceItemButton')),
    );

    final edited = await tester.runAsync<MaintenanceItem?>(
      () => services.maintenanceItems.getById(item.id),
    );
    final savedEdit = edited ?? fail('Expected edited maintenance item.');
    expect(savedEdit.name, 'Engine Oil Plus');
    expect(savedEdit.mileageInterval, 9000);
    expect(savedEdit.isArchived, isFalse);

    await _tapAndPump(
      tester,
      find.byKey(const Key('archiveMaintenanceItemButton')),
    );
    await _pumpUntilFound(tester, find.text('Archive item?'));
    await _tapAndPump(tester, find.text('Cancel').last);
    await _pumpUntilGone(tester, find.text('Archive item?'));
    expect(tester.takeException(), isNull);

    await _tapAndPump(
      tester,
      find.byKey(const Key('archiveMaintenanceItemButton')),
    );
    await _pumpUntilFound(tester, find.text('Archive item?'));
    await _tapAndRunAsync(
      tester,
      find.byKey(const Key('confirmArchiveMaintenanceItemButton')),
    );
    await _pumpUntilFound(
      tester,
      find.text('No maintenance items have been added yet.'),
    );

    final archivedItems = await tester.runAsync<List<MaintenanceItem>>(
      () => services.maintenanceItems.listForVehicle(
        vehicle.id,
        includeArchived: true,
      ),
    );
    final savedArchivedItems =
        archivedItems ?? fail('Expected archived maintenance item.');
    expect(savedArchivedItems.single.isArchived, isTrue);
  });

  testWidgets('Add Service saves multiple items and opens from History', (
    tester,
  ) async {
    final services = createTestServices();
    late Vehicle vehicle;
    late MaintenanceItem oil;
    late MaintenanceItem filter;
    await tester.runAsync(() async {
      vehicle = await services.vehicleService.addVehicle(
        _draft('Commuter', 64000),
      );
      oil = await services.maintenanceItemService.createMaintenanceItem(
        MaintenanceItemDraft(
          vehicleId: vehicle.id,
          name: 'Engine Oil',
          mileageInterval: 8000,
        ),
      );
      filter = await services.maintenanceItemService.createMaintenanceItem(
        MaintenanceItemDraft(
          vehicleId: vehicle.id,
          name: 'Oil Filter',
          mileageInterval: 8000,
        ),
      );
    });

    final controller = await _pumpApp(
      tester,
      services,
      find.byKey(const Key('mainActionButton')),
    );
    expect(controller.selectedVehicle?.id, vehicle.id);

    await _openActionForm(
      tester,
      actionKey: const Key('actionServiceTile'),
      readyKey: const Key('serviceTotalCostField'),
    );
    await _waitForServiceItemsLoaded(tester);
    await tester.enterText(
      find.byKey(const Key('serviceOdometerField')),
      '66000',
    );
    await tester.enterText(
      find.byKey(const Key('serviceTotalCostField')),
      '240',
    );
    await tester.enterText(
      find.byKey(const Key('serviceGarageField')),
      'ABC Garage',
    );
    await _selectServiceItem(tester, oil, allocatedCost: '120');
    await _selectServiceItem(tester, filter, allocatedCost: '40');

    await _tapAndRunAsync(tester, find.byKey(const Key('saveServiceButton')));
    await _pumpUntilFound(tester, find.text('Home'));
    expect(find.text('£240.00'), findsWidgets);

    final records = await tester.runAsync<List<ServiceRecord>>(
      () => services.serviceRecords.listForVehicle(vehicle.id),
    );
    final savedRecords = records ?? fail('Expected saved service record.');
    expect(savedRecords, hasLength(1));
    final service = savedRecords.single;
    expect(service.totalCostMinor, 24000);

    final serviceItems = await tester.runAsync<List<ServiceItem>>(
      () => services.serviceRecords.listItemsForService(service.id),
    );
    final savedServiceItems =
        serviceItems ?? fail('Expected saved service items.');
    expect(savedServiceItems, hasLength(2));
    expect(
      savedServiceItems.map((item) => item.maintenanceItemId),
      unorderedEquals([oil.id, filter.id]),
    );
    expect(
      savedServiceItems.map((item) => item.itemName),
      unorderedEquals(['Engine Oil', 'Oil Filter']),
    );
    expect(
      savedServiceItems.map((item) => item.allocatedCostMinor),
      unorderedEquals([12000, 4000]),
    );

    final activities = await tester.runAsync<List<DailyActivity>>(
      () =>
          controller.historyForSelectedVehicle(type: DailyActivityType.service),
    );
    final serviceActivities =
        activities ?? fail('Expected service History activity.');
    expect(serviceActivities, hasLength(1));
    final serviceActivity = serviceActivities.single;
    expect(serviceActivity.recordId, service.id);
    expect(serviceActivity.title, 'Service');
    expect(serviceActivity.subtitle, contains('ABC Garage'));
    expect(serviceActivity.subtitle, contains('Engine Oil + 1 more'));
    expect(serviceActivity.amountMinor, 24000);

    final spend = await tester.runAsync<int>(
      () => services.financialSummary.monthSpendForVehicle(vehicle.id),
    );
    expect(spend ?? fail('Expected monthly spend.'), 24000);
    final expenses = await tester.runAsync(
      () => services.expenses.listForVehicle(vehicle.id),
    );
    expect(expenses ?? fail('Expected expense list.'), isEmpty);

    await _openHistoryScreen(tester);
    final serviceRow = find.byKey(Key('historyActivity_service_${service.id}'));
    await _pumpUntilFound(tester, serviceRow);
    await _tapAndPump(
      tester,
      find.descendant(
        of: find.byKey(const Key('historyFilterField')),
        matching: find.text('Service'),
      ),
    );
    await _pumpUntilGone(tester, find.text('Odometer'));
    await _pumpUntilFound(tester, serviceRow);
    expect(
      find.descendant(of: serviceRow, matching: find.text('Service')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: serviceRow,
        matching: find.textContaining('Engine Oil + 1 more'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: serviceRow, matching: find.text('£240.00')),
      findsOneWidget,
    );

    await _tapAndPump(tester, serviceRow);
    await _pumpUntilFound(tester, find.byKey(const Key('deleteServiceButton')));
    await _waitForServiceItemsLoaded(tester);
    expect(find.byKey(const Key('serviceTotalCostField')), findsOneWidget);
  });

  testWidgets('Reminders Record Service renews the maintenance cycle', (
    tester,
  ) async {
    final services = createTestServices();
    late Vehicle vehicle;
    late MaintenanceItem oil;
    await tester.runAsync(() async {
      vehicle = await services.vehicleService.addVehicle(
        _draft('Commuter', 73000),
      );
      oil = await services.maintenanceItemService.createMaintenanceItem(
        MaintenanceItemDraft(
          vehicleId: vehicle.id,
          name: 'Engine Oil',
          mileageInterval: 8000,
        ),
      );
      await services.serviceRecordService.createBaselineCompletion(
        item: oil,
        eventDateTime: DateTime.utc(2026, 1, 1),
        odometer: 65000,
      );
    });

    final controller = await _pumpApp(
      tester,
      services,
      find.byKey(const Key('mainActionButton')),
    );
    expect(controller.selectedVehicle?.id, vehicle.id);

    await _tapAndPump(tester, find.text('Reminders').last);
    await _pumpUntilFound(tester, find.byKey(Key('recordService_${oil.id}')));
    expect(find.textContaining('Due now'), findsWidgets);

    await _tapAndPump(tester, find.byKey(Key('recordService_${oil.id}')));
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('serviceTotalCostField')),
    );
    await _waitForServiceItemsLoaded(tester);
    await tester.enterText(
      find.byKey(const Key('serviceOdometerField')),
      '73000',
    );
    await tester.enterText(
      find.byKey(const Key('serviceTotalCostField')),
      '100',
    );

    final checkbox = find.byKey(Key('serviceItemCheckbox_${oil.id}'));
    await _scrollUntilFound(tester, checkbox);
    expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);

    await _tapAndRunAsync(tester, find.byKey(const Key('saveServiceButton')));
    final serviceRecords = await tester.runAsync<List<ServiceRecord>>(
      () => services.serviceRecords.listForVehicle(vehicle.id),
    );
    final savedServiceRecords =
        serviceRecords ?? fail('Expected saved service records.');
    final completedServices = savedServiceRecords
        .where((record) => !record.isBaseline)
        .toList();
    expect(completedServices, hasLength(1));

    final renewedItems = await tester.runAsync<List<ServiceItem>>(
      () => services.serviceRecords.listItemsForService(
        completedServices.single.id,
      ),
    );
    final savedRenewedItems =
        renewedItems ?? fail('Expected renewed service item.');
    expect(savedRenewedItems, hasLength(1));
    expect(savedRenewedItems.single.maintenanceItemId, oil.id);

    final reminderRow = find.byKey(Key('reminder_${oil.id}'));
    await _pumpUntilFound(tester, reminderRow);
    await _pumpUntilFound(
      tester,
      find.descendant(of: reminderRow, matching: find.textContaining('Normal')),
    );
    await _pumpUntilFound(
      tester,
      find.descendant(
        of: reminderRow,
        matching: find.textContaining('8,000 mi remaining'),
      ),
    );
    expect(find.text('All good'), findsWidgets);

    final reminders = await tester.runAsync(
      () => services.maintenanceItemService.remindersForVehicle(
        vehicle.id,
        currentOdometer: 73000,
        asOf: DateTime.utc(2026, 9, 5),
      ),
    );
    final savedReminders =
        reminders ?? fail('Expected recalculated maintenance reminder.');
    final reminder = savedReminders.single;
    expect(reminder.state, MaintenanceReminderState.normal);
    expect(reminder.latestCompletionOdometer, 73000);
    expect(reminder.nextMileageDue, 81000);
    expect(reminder.milesRemaining, 8000);
    expect(reminder.completions, hasLength(2));
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
  final target = await _pumpUntilHittable(tester, finder);
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _openActionSheet(WidgetTester tester) async {
  await _tapAndPump(tester, find.byKey(const Key('mainActionButton')));
  await _pumpUntilFound(tester, find.byKey(const Key('actionRefuelTile')));
}

Future<void> _openActionForm(
  WidgetTester tester, {
  required Key actionKey,
  required Key readyKey,
}) async {
  await _openActionSheet(tester);
  await _tapAndPump(tester, find.byKey(actionKey));
  await _pumpUntilFound(tester, find.byKey(readyKey));
}

Future<void> _openMaintenanceScreen(WidgetTester tester) async {
  await _tapAndPump(tester, find.text('More').last);
  await _pumpUntilFound(tester, find.byKey(const Key('moreMaintenanceTile')));
  await _tapAndPump(tester, find.byKey(const Key('moreMaintenanceTile')));
  await _pumpUntilFound(tester, find.byKey(const Key('maintenanceAddButton')));
}

Future<void> _openHistoryScreen(WidgetTester tester) async {
  await _tapAndPump(tester, find.text('More').last);
  await _pumpUntilFound(tester, find.text('History'));
  await _tapAndPump(tester, find.text('History').first);
  await _pumpUntilFound(tester, find.byKey(const Key('historyFilterField')));
}

Future<void> _selectServiceItem(
  WidgetTester tester,
  MaintenanceItem item, {
  String? allocatedCost,
}) async {
  final checkbox = find.byKey(Key('serviceItemCheckbox_${item.id}'));
  await _scrollUntilFound(tester, checkbox);
  await _tapAndPump(tester, checkbox);
  if (allocatedCost == null) {
    return;
  }
  final costField = find.byKey(Key('serviceItemCost_${item.id}'));
  await _scrollUntilFound(tester, costField);
  await tester.enterText(costField, allocatedCost);
  await tester.pump();
}

Future<void> _waitForServiceItemsLoaded(WidgetTester tester) async {
  final loaded = find.byKey(const Key('serviceItemsLoaded'));
  final empty = find.byKey(const Key('serviceItemsEmpty'));

  for (var index = 0; index < 50; index += 1) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
    if (loaded.evaluate().isNotEmpty || empty.evaluate().isNotEmpty) {
      break;
    }
  }

  expect(
    empty,
    findsNothing,
    reason: 'Expected tracked maintenance items in the Service form.',
  );
  expect(
    loaded,
    findsOneWidget,
    reason: 'Expected the Service form maintenance-items query to finish.',
  );
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
  await tester.pump();
  await _pumpUntilFound(tester, find.text(label));
  await tester.tap(find.text(label).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
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
  for (var attempt = 0; attempt < 30; attempt += 1) {
    final hittable = finder.hitTestable();
    if (hittable.evaluate().isNotEmpty) {
      return;
    }

    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder);
      await tester.pump();
      if (hittable.evaluate().isNotEmpty) {
        return;
      }
    }

    final scrollable = _activeScrollable();
    await tester.drag(scrollable, const Offset(0, -240));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  expect(
    finder,
    findsWidgets,
    reason: 'Could not find target after scrolling the active route.',
  );
  await _pumpUntilHittable(tester, finder);
}

Future<void> _tapAndRunAsync(WidgetTester tester, Finder finder) async {
  final target = await _pumpUntilHittable(tester, finder);
  await tester.runAsync(() async {
    await tester.tap(target);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
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
  expect(
    finder.hitTestable(),
    findsWidgets,
    reason: 'Expected target to be visible and hittable.',
  );
  return finder.hitTestable();
}

Finder _activeScrollable() {
  final scrollable = find.byType(ListView).hitTestable();
  expect(
    scrollable,
    findsOneWidget,
    reason:
        'Expected exactly one onstage hittable ListView in the active route.',
  );
  return scrollable;
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
