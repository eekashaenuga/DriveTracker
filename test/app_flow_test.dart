import 'dart:io';

import 'package:drivetracker/app/app.dart';
import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/app/theme/dt_theme.dart';
import 'package:drivetracker/features/attachments/domain/attachment.dart';
import 'package:drivetracker/features/attachments/domain/attachment_io.dart';
import 'package:drivetracker/features/daily_records/domain/daily_activity.dart';
import 'package:drivetracker/features/daily_records/domain/expense.dart';
import 'package:drivetracker/features/daily_records/domain/income.dart';
import 'package:drivetracker/features/daily_records/domain/record_category.dart';
import 'package:drivetracker/features/daily_records/domain/refuel.dart';
import 'package:drivetracker/features/documents/domain/vehicle_document.dart';
import 'package:drivetracker/features/home/presentation/home_screen.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_item.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_reminder.dart';
import 'package:drivetracker/features/maintenance/domain/service_record.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

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
    final now = DateTime.utc(2026, 9, 20, 12);
    late Vehicle commuter;
    late Vehicle weekend;
    await tester.runAsync(() async {
      commuter = await services.vehicleService.addVehicle(
        _draft('Commuter', 1000),
      );
      weekend = await services.vehicleService.addVehicle(
        _draft('Weekend', 25000),
      );
      await services.refuelService.createRefuel(
        _refuelDraft(
          commuter.id,
          eventDateTime: DateTime.utc(2026, 9, 16, 8),
          odometer: 1100,
          totalCostMinor: 5000,
          unitPriceMicrosPerLitre: 1250000,
        ),
      );
      await services.refuelService.createRefuel(
        _refuelDraft(
          weekend.id,
          eventDateTime: DateTime.utc(2026, 9, 18, 8),
          odometer: 25100,
          totalCostMinor: 6000,
          unitPriceMicrosPerLitre: 1500000,
        ),
      );
    });

    await _pumpApp(
      tester,
      services,
      find.byKey(const Key('selectedVehicleButton')),
      now: now,
    );

    expect(find.text('Weekend'), findsWidgets);
    expect(find.text('25,100 mi'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const Key('homeMonthSpendMetric')),
        matching: find.text('£60.00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('homeFuelPriceMetric')),
        matching: find.text('150 p/L'),
      ),
      findsOneWidget,
    );
    await _tapAndPump(tester, find.byKey(const Key('selectedVehicleButton')));
    await _pumpUntilFound(tester, find.text('Select vehicle'));
    await _tapAndRunAsync(tester, find.text('Commuter').last);
    await _pumpUntilFound(tester, find.text('1,100 mi'));

    expect(find.text('Commuter'), findsWidgets);
    expect(find.text('1,100 mi'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const Key('homeMonthSpendMetric')),
        matching: find.text('£50.00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('homeFuelPriceMetric')),
        matching: find.text('125 p/L'),
      ),
      findsOneWidget,
    );
    await _scrollUntilFound(tester, find.byKey(const Key('homeSpendingTrend')));
    expect(find.text('Sep · £50.00 spent'), findsOneWidget);
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

  testWidgets('Home dashboard renders stored summaries', (tester) async {
    final services = createTestServices();
    final now = DateTime.utc(2026, 9, 20, 12);
    late Vehicle vehicle;
    late String serviceId;
    await tester.runAsync(() async {
      final expenseCategory = await _firstCategory(
        services,
        RecordCategoryType.expense,
      );
      final incomeCategory = await _firstCategory(
        services,
        RecordCategoryType.income,
      );
      vehicle = await services.vehicleService.addVehicle(
        _draft('Commuter', 64000),
      );
      await services.refuelService.createRefuel(
        _refuelDraft(
          vehicle.id,
          eventDateTime: DateTime.utc(2026, 8, 10, 8),
          odometer: 64100,
          totalCostMinor: 5000,
          unitPriceMicrosPerLitre: 1250000,
        ),
      );
      await services.refuelService.createRefuel(
        _refuelDraft(
          vehicle.id,
          eventDateTime: DateTime.utc(2026, 9, 10, 8),
          odometer: 64500,
          totalCostMinor: 6000,
          unitPriceMicrosPerLitre: 1500000,
        ),
      );
      await services.expenseService.createExpense(
        ExpenseDraft(
          vehicleId: vehicle.id,
          categoryId: expenseCategory.id,
          eventDateTime: DateTime.utc(2026, 9, 11, 8),
          amountMinor: 1200,
          merchant: 'Tyre Shop',
        ),
      );
      await services.incomeService.createIncome(
        IncomeDraft(
          vehicleId: vehicle.id,
          categoryId: incomeCategory.id,
          eventDateTime: DateTime.utc(2026, 9, 12, 8),
          amountMinor: 4500,
          source: 'Mileage reclaim',
        ),
      );
      final service = await services.serviceRecordService.createServiceRecord(
        ServiceRecordDraft(
          vehicleId: vehicle.id,
          eventDateTime: DateTime.utc(2026, 9, 13, 8),
          odometer: 64600,
          totalCostMinor: 9000,
          garage: 'ABC Garage',
          items: const [ServiceItemDraft(itemName: 'Inspection')],
        ),
      );
      serviceId = service.record.id;
      final oil = await services.maintenanceItemService.createMaintenanceItem(
        MaintenanceItemDraft(
          vehicleId: vehicle.id,
          name: 'Engine Oil',
          mileageInterval: 8000,
        ),
      );
      await services.serviceRecordService.createBaselineCompletion(
        item: oil,
        eventDateTime: DateTime.utc(2026, 5, 1, 8),
        odometer: 56600,
      );
    });

    await _pumpApp(
      tester,
      services,
      find.byKey(const Key('homeMonthSpendMetric')),
      now: now,
    );

    expect(find.text('Commuter'), findsWidgets);
    expect(find.text('64,600 mi'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const Key('homeMonthSpendMetric')),
        matching: find.text('£162.00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('homeFuelPriceMetric')),
        matching: find.text('150 p/L'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('homeFuelEconomyMetric')),
        matching: find.text('45.5 UK MPG'),
      ),
      findsOneWidget,
    );

    await _scrollUntilFound(tester, find.text('Engine Oil'));
    expect(find.textContaining('Due now'), findsWidgets);
    expect(find.byKey(const Key('homeMaintenanceProgress')), findsOneWidget);
    await _tapAndPump(
      tester,
      find.byKey(const Key('homeMaintenanceAttentionTile')),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('editMaintenanceItemButton')),
    );
    expect(find.text('Engine Oil'), findsWidgets);
    await _tapAndPump(tester, find.byTooltip('Back'));
    await _pumpUntilFound(tester, find.byKey(const Key('homeDashboardList')));

    await _scrollUntilFound(tester, find.byKey(const Key('homeSpendingTrend')));
    expect(find.byKey(const Key('homeTrendBar_2026_8')), findsOneWidget);
    expect(find.byKey(const Key('homeTrendBar_2026_9')), findsOneWidget);
    expect(find.text('Sep · £162.00 spent'), findsOneWidget);
    expect(find.text('£0.00'), findsNothing);
    expect(find.text('£50.00'), findsWidgets);
    expect(find.text('£162.00'), findsWidgets);
    await _tapAndPump(tester, find.byKey(const Key('homeTrendMonth_2026_7')));
    await _pumpUntilFound(tester, find.text('Jul · £0.00 spent'));
    expect(find.text('£0.00'), findsOneWidget);

    final serviceRow = find.byKey(Key('homeActivity_service_$serviceId'));
    await _scrollUntilFound(tester, serviceRow);
    expect(serviceRow, findsOneWidget);
    expect(
      find.descendant(of: serviceRow, matching: find.text('Service')),
      findsOneWidget,
    );
  });

  testWidgets('Home activity opens records and View all opens History', (
    tester,
  ) async {
    final services = createTestServices();
    final now = DateTime.utc(2026, 9, 20, 12);
    late String refuelId;
    await tester.runAsync(() async {
      final vehicle = await services.vehicleService.addVehicle(
        _draft('Commuter', 64000),
      );
      final refuel = await services.refuelService.createRefuel(
        _refuelDraft(
          vehicle.id,
          eventDateTime: DateTime.utc(2026, 9, 20, 10),
          odometer: 64100,
          totalCostMinor: 5000,
          unitPriceMicrosPerLitre: 1250000,
        ),
      );
      refuelId = refuel.id;
    });

    await _pumpApp(
      tester,
      services,
      find.byKey(const Key('homeMonthSpendMetric')),
      now: now,
    );

    await _scrollUntilFound(
      tester,
      find.byKey(const Key('homeViewAllHistoryButton')),
    );
    await _tapAndPump(
      tester,
      find.byKey(const Key('homeViewAllHistoryButton')),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(Key('historyActivity_refuel_$refuelId')),
    );
    expect(find.text('History'), findsWidgets);

    await _tapAndPump(tester, find.byTooltip('Back'));
    await _pumpUntilFound(tester, find.byKey(const Key('homeDashboardList')));

    final activityRow = find.byKey(Key('homeActivity_refuel_$refuelId'));
    await _scrollUntilFound(tester, activityRow);
    expect(
      find.descendant(of: activityRow, matching: find.textContaining('Today,')),
      findsOneWidget,
    );
    await _tapAndRunAsync(tester, activityRow);
    await _pumpUntilFound(tester, find.text('Edit refuel'));

    final totalCostField = tester.widget<TextFormField>(
      find.byKey(const Key('refuelTotalCostField')),
    );
    expect(totalCostField.controller?.text, '50.00');
  });

  testWidgets('Home dashboard handles dark narrow empty-spend state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final services = createTestServices();
    final now = DateTime.utc(2026, 9, 20, 12);
    const longVehicleName = 'Very Long Commuter Name That Should Ellipsize';
    await tester.runAsync(() async {
      await services.vehicleService.addVehicle(
        _draft(longVehicleName, 1234567),
      );
    });

    final controller = await _pumpApp(
      tester,
      services,
      find.byKey(const Key('homeMonthSpendMetric')),
      now: now,
    );
    await tester.runAsync(() => controller.setThemeMode(ThemeMode.dark));
    await tester.pump();

    expect(find.text(longVehicleName), findsWidgets);
    expect(find.text('1,234,567 mi'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const Key('homeFuelPriceMetric')),
        matching: find.text('No fuel data'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('homeFuelEconomyMetric')),
        matching: find.text('Not enough data'),
      ),
      findsOneWidget,
    );
    await _scrollUntilFound(tester, find.text('No maintenance due soon'));
    expect(find.byKey(const Key('homeMaintenanceProgress')), findsNothing);
    await _scrollUntilFound(
      tester,
      find.byKey(const Key('homeSpendingTrendEmpty')),
    );

    expect(find.text('No spending trend yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home dashboard supports reduced-motion media settings', (
    tester,
  ) async {
    final services = createTestServices();
    final now = DateTime.utc(2026, 9, 20, 12);
    await tester.runAsync(() async {
      await services.vehicleService.addVehicle(_draft('Commuter', 64000));
    });
    final controller = DriveTrackerController(
      database: services.database,
      clock: () => now,
    );
    addTearDown(controller.dispose);
    await tester.runAsync(controller.initialize);

    await tester.pumpWidget(
      MaterialApp(
        theme: DTTheme.light(),
        home: ChangeNotifierProvider.value(
          value: controller,
          child: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: HomeScreen(),
          ),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.byKey(const Key('homeDashboardList')));

    expect(find.text('Commuter'), findsWidgets);
    expect(find.text('64,000 mi'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('central action opens Daily Records actions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
    expect(find.byKey(const Key('actionOdometerTile')), findsOneWidget);
    expect(find.text('Odometer'), findsWidgets);
    expect(tester.takeException(), isNull);
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
    final archivedState = await _waitForMaintenanceArchive(
      tester,
      services,
      vehicle.id,
      item.id,
    );
    expect(archivedState.activeItems, isEmpty);
    final savedArchivedItems = archivedState.allItems;
    expect(savedArchivedItems, hasLength(1));
    expect(savedArchivedItems.single.id, item.id);
    expect(savedArchivedItems.single.name, 'Engine Oil Plus');
    expect(savedArchivedItems.single.mileageInterval, 9000);
    expect(savedArchivedItems.single.isArchived, isTrue);

    await _pumpUntilFound(
      tester,
      find.byKey(const Key('maintenanceAddButton')),
    );
    await _pumpUntilFound(
      tester,
      find.text('No maintenance items have been added yet.'),
    );
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
    await _pumpUntilGone(
      tester,
      _historyActivityRowsForType(DailyActivityType.odometer),
    );
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

    await _scrollUntilFound(tester, serviceRow);
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

  testWidgets('Documents add attachment reminder and archive flow', (
    tester,
  ) async {
    final services = createTestServices();
    final now = DateTime(2026, 9, 20, 12);
    late Vehicle vehicle;
    await tester.runAsync(() async {
      vehicle = await services.vehicleService.addVehicle(
        _draft('Commuter', 64000),
      );
    });

    await _pumpApp(
      tester,
      services,
      find.byKey(const Key('mainActionButton')),
      now: now,
    );

    await _openDocumentsScreen(tester);
    expect(find.text('No documents yet'), findsOneWidget);
    await _tapAndPump(tester, find.byKey(const Key('emptyAddDocumentButton')));
    await _pumpUntilFound(tester, find.byKey(const Key('documentTitleField')));

    await tester.enterText(
      find.byKey(const Key('documentTitleField')),
      'Insurance policy',
    );
    await _scrollUntilFound(tester, find.byTooltip('Choose Expiry date'));
    await _tapAndPump(tester, find.byTooltip('Choose Expiry date'));
    await _tapDatePickerDay(tester, 25);
    await _tapDatePickerTextAction(tester, 'OK');
    await _scrollUntilFound(
      tester,
      find.byKey(const Key('documentProviderField')),
    );
    await tester.enterText(
      find.byKey(const Key('documentProviderField')),
      'Admiral',
    );
    await _scrollUntilFound(
      tester,
      find.byKey(const Key('documentReferenceField')),
    );
    await tester.enterText(
      find.byKey(const Key('documentReferenceField')),
      'ABC123',
    );
    await _tapAndRunAsync(tester, find.byKey(const Key('saveDocumentButton')));

    final documents = await tester.runAsync<List<VehicleDocument>>(
      () => services.documents.listForVehicle(vehicle.id),
    );
    final document = (documents ?? fail('Expected saved document.')).single;
    final card = find.byKey(Key('documentCard_${document.id}'));
    await _pumpUntilFound(tester, card);
    expect(find.text('Insurance policy'), findsWidgets);
    expect(find.textContaining('Expires in 5 days'), findsWidgets);

    await _tapAndPump(tester, card);
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('documentDetailsLoaded')),
    );
    final source = await tester.runAsync<File>(
      () => _writeAttachmentSource(services, 'policy-proof.pdf'),
    );
    final attachmentSource =
        source ?? fail('Expected attachment source file to be created.');
    services.attachmentPicker.nextSource = AttachmentSource(
      sourcePath: attachmentSource.path,
      fileName: 'policy proof.pdf',
      mimeType: 'application/pdf',
      fileSize: 4,
    );
    await _tapAndRunAsync(
      tester,
      find.byKey(Key('addAttachment_${document.id}')),
    );
    await _pumpUntilFound(tester, find.text('policy proof.pdf'));
    expect(services.attachmentPicker.pickCount, 1);
    expect(
      await tester.runAsync(
        () => services.attachments.listForParent(
          AttachmentParentType.document,
          document.id,
        ),
      ),
      hasLength(1),
    );

    await _tapBack(tester);
    await _tapBack(tester);
    await _tapAndPump(tester, find.text('Reminders').last);
    await _pumpUntilFound(
      tester,
      find.byKey(Key('documentReminder_${document.id}')),
    );
    expect(find.text('Insurance: Insurance policy'), findsOneWidget);

    await _tapAndPump(
      tester,
      find.byKey(Key('documentReminder_${document.id}')),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('documentDetailsLoaded')),
    );
    await _tapAndPump(tester, find.byTooltip('Document actions'));
    await _tapAndRunAsync(tester, find.text('Archive'));
    final archived = await _waitForDocumentArchived(
      tester,
      services,
      document.id,
    );
    expect(archived.isArchived, isTrue);
    await _tapBack(tester);
    await _pumpUntilGone(
      tester,
      find.byKey(Key('documentReminder_${document.id}')),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Insights renders real data and drills down to filtered History',
    (tester) async {
      final services = createTestServices();
      final now = DateTime.utc(2026, 9, 20, 12);
      late Vehicle vehicle;
      late String expenseId;
      await tester.runAsync(() async {
        final parking = await _categoryById(services, 'cat_expense_parking');
        final incomeCategory = await _categoryById(
          services,
          'cat_income_rideshare',
        );
        vehicle = await services.vehicleService.addVehicle(
          _draft('Commuter', 64000),
        );
        await services.refuelService.createRefuel(
          _refuelDraft(
            vehicle.id,
            eventDateTime: DateTime.utc(2026, 9, 4, 8),
            odometer: 64100,
            totalCostMinor: 5000,
            volumeMillilitres: 40000,
            unitPriceMicrosPerLitre: 1250000,
          ),
        );
        final expense = await services.expenseService.createExpense(
          ExpenseDraft(
            vehicleId: vehicle.id,
            categoryId: parking.id,
            eventDateTime: DateTime.utc(2026, 9, 5, 8),
            amountMinor: 1200,
            merchant: 'Station Car Park',
            notes: 'airport run',
          ),
        );
        expenseId = expense.id;
        await services.incomeService.createIncome(
          IncomeDraft(
            vehicleId: vehicle.id,
            categoryId: incomeCategory.id,
            eventDateTime: DateTime.utc(2026, 9, 6, 8),
            amountMinor: 4500,
            source: 'Mileage reclaim',
          ),
        );
        await services.serviceRecordService.createServiceRecord(
          ServiceRecordDraft(
            vehicleId: vehicle.id,
            eventDateTime: DateTime.utc(2026, 9, 7, 8),
            odometer: 64600,
            totalCostMinor: 9000,
            garage: 'ABC Garage',
            items: const [ServiceItemDraft(itemName: 'Inspection')],
          ),
        );
      });

      await _pumpApp(
        tester,
        services,
        find.byKey(const Key('mainActionButton')),
        now: now,
      );
      await _tapAndPump(tester, find.text('Insights').last);
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('insightsScreenList')),
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('insightsTotalSpendMetric')),
          matching: find.text('£152.00'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('insightsDistanceMetric')),
          matching: find.text('600 mi'),
        ),
        findsOneWidget,
      );
      await _scrollUntilFound(
        tester,
        find.byKey(const Key('insightsSpendingChart')),
      );

      await _tapAndPump(
        tester,
        find.byKey(const Key('insightsSpendingBucket_0')),
      );
      expect(
        find.byKey(const Key('insightsSelectedSpendingBucket')),
        findsOneWidget,
      );

      await _scrollUntilFound(
        tester,
        find.byKey(const Key('insightsBreakdown_cat_expense_parking')),
      );
      await _tapAndPump(
        tester,
        find.byKey(const Key('insightsBreakdown_cat_expense_parking')),
      );
      await _pumpUntilFound(tester, find.textContaining('Parking · £12.00'));
      await _tapAndPump(
        tester,
        find.byKey(const Key('insightsBreakdownDrilldownButton')),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(Key('historyActivity_expense_$expenseId')),
      );

      expect(find.text('History'), findsWidgets);
      expect(find.text('Parking'), findsWidgets);
      expect(find.textContaining('Station Car Park / Expense'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Insights handles all vehicles and custom range controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final services = createTestServices();
    final now = DateTime.utc(2026, 9, 20, 12);
    await tester.runAsync(() async {
      final category = await _categoryById(services, 'cat_expense_parking');
      final commuter = await services.vehicleService.addVehicle(
        _draft('Commuter', 1000),
      );
      final weekend = await services.vehicleService.addVehicle(
        _draft('Weekend', 5000),
      );
      await services.refuelService.createRefuel(
        _refuelDraft(
          commuter.id,
          eventDateTime: DateTime.utc(2026, 9, 4, 8),
          odometer: 1100,
          totalCostMinor: 5000,
        ),
      );
      await services.expenseService.createExpense(
        ExpenseDraft(
          vehicleId: weekend.id,
          categoryId: category.id,
          eventDateTime: DateTime.utc(2026, 9, 5, 8),
          amountMinor: 2000,
        ),
      );
    });

    final controller = await _pumpApp(
      tester,
      services,
      find.byKey(const Key('mainActionButton')),
      now: now,
    );
    await tester.runAsync(() => controller.setThemeMode(ThemeMode.dark));
    await tester.pump();
    await _tapAndPump(tester, find.text('Insights').last);
    await _pumpUntilFound(tester, find.byKey(const Key('insightsScreenList')));

    await _selectDropdownItem(
      tester,
      field: find.byKey(const Key('insightsVehicleSelector')),
      label: 'All vehicles',
    );
    await _pumpUntilFound(
      tester,
      find.text('Select one vehicle for distance-based metrics.'),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('insightsTotalSpendMetric')),
        matching: find.text('£70.00'),
      ),
      findsOneWidget,
    );

    await _tapInsightsCustomRangeButton(tester);
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('insightsCustomRangePicker')),
    );
    await _selectDatePickerRange(tester, startDay: 4, endDay: 4);
    await _pumpUntilFound(tester, find.text('4 Sep 2026'));
    await _pumpUntilFound(
      tester,
      find.descendant(
        of: find.byKey(const Key('insightsTotalSpendMetric')),
        matching: find.text('£50.00'),
      ),
    );

    await _tapInsightsCustomRangeButton(tester);
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('insightsCustomRangePicker')),
    );
    await _tapDatePickerDay(tester, 5);
    await _closeDateRangePicker(tester);
    await _pumpUntilGone(
      tester,
      find.byKey(const Key('insightsCustomRangePicker')),
    );
    expect(find.text('4 Sep 2026'), findsOneWidget);
    await _pumpUntilFound(tester, find.byKey(const Key('insightsScreenList')));

    await _tapInsightsCustomRangeButton(tester);
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('insightsCustomRangePicker')),
    );
    await _tapDatePickerTextAction(tester, 'Apply');
    await _pumpUntilGone(
      tester,
      find.byKey(const Key('insightsCustomRangePicker')),
    );
    expect(find.text('4 Sep 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Insights visual charts are compact and selectable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final services = createTestServices();
    final now = DateTime.utc(2026, 9, 20, 12);
    await tester.runAsync(() async {
      final parking = await _categoryById(services, 'cat_expense_parking');
      final incomeCategory = await _categoryById(
        services,
        'cat_income_rideshare',
      );
      final vehicle = await services.vehicleService.addVehicle(
        _draft('Long Distance Commuter Vehicle', 64000),
      );
      await services.refuelService.createRefuel(
        _refuelDraft(
          vehicle.id,
          eventDateTime: DateTime.utc(2026, 9, 1, 8),
          odometer: 65000,
          totalCostMinor: 5000,
          volumeMillilitres: 40000,
          unitPriceMicrosPerLitre: 1250000,
        ),
      );
      await services.refuelService.createRefuel(
        _refuelDraft(
          vehicle.id,
          eventDateTime: DateTime.utc(2026, 9, 5, 8),
          odometer: 65200,
          totalCostMinor: 3200,
          volumeMillilitres: 20000,
          unitPriceMicrosPerLitre: 1600000,
        ),
      );
      await services.refuelService.createRefuel(
        _refuelDraft(
          vehicle.id,
          eventDateTime: DateTime.utc(2026, 9, 12, 8),
          odometer: 65500,
          totalCostMinor: 5400,
          volumeMillilitres: 45000,
          unitPriceMicrosPerLitre: 1200000,
        ),
      );
      await services.expenseService.createExpense(
        ExpenseDraft(
          vehicleId: vehicle.id,
          categoryId: parking.id,
          eventDateTime: DateTime.utc(2026, 9, 3, 8),
          amountMinor: 123456789,
          merchant: 'Airport Long Stay',
        ),
      );
      await services.incomeService.createIncome(
        IncomeDraft(
          vehicleId: vehicle.id,
          categoryId: incomeCategory.id,
          eventDateTime: DateTime.utc(2026, 9, 18, 8),
          amountMinor: 9876543,
          source: 'Mileage reclaim',
        ),
      );
    });

    final controller = await _pumpApp(
      tester,
      services,
      find.byKey(const Key('mainActionButton')),
      now: now,
    );
    await tester.runAsync(() => controller.setThemeMode(ThemeMode.dark));
    await tester.pump();
    await _tapAndPump(tester, find.text('Insights').last);
    await _pumpUntilFound(tester, find.byKey(const Key('insightsScreenList')));

    expect(find.byKey(const Key('insightsTotalSpendMetric')), findsOneWidget);
    expect(find.byKey(const Key('insightsDistanceMetric')), findsOneWidget);
    expect(find.byKey(const Key('insightsFuelEconomyMetric')), findsOneWidget);
    expect(
      find.byKey(const Key('insightsCostPerDistanceMetric')),
      findsOneWidget,
    );

    await _scrollUntilFound(
      tester,
      find.byKey(const Key('insightsSpendingChart')),
    );
    final zeroBar = tester.widget<SizedBox>(
      find.byKey(const Key('insightsSpendingBucketBar_2')),
    );
    expect(zeroBar.height, 0);
    await _tapAndPump(
      tester,
      find.byKey(const Key('insightsSpendingBucket_2')),
    );
    expect(
      find.byKey(const Key('insightsSelectedSpendingBucket')),
      findsOneWidget,
    );

    await _scrollUntilFound(
      tester,
      find.byKey(const Key('insightsFuelEconomyChart')),
    );
    await _tapAndPump(
      tester,
      find.byKey(const Key('insightsFuelEconomyPoint_0')),
    );
    expect(
      find.byKey(const Key('insightsSelectedFuelEconomyPoint')),
      findsOneWidget,
    );

    await _scrollUntilFound(
      tester,
      find.byKey(const Key('insightsFuelPriceChart')),
    );
    await _tapAndPump(
      tester,
      find.byKey(const Key('insightsFuelPricePoint_0')),
    );
    expect(
      find.byKey(const Key('insightsSelectedFuelPricePoint')),
      findsOneWidget,
    );

    await _scrollUntilFound(
      tester,
      find.byKey(const Key('insightsMileagePanel')),
    );
    await _tapAndPump(tester, find.byKey(const Key('insightsMileagePoint_0')));
    expect(
      find.byKey(const Key('insightsSelectedMileagePoint')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('History filters by type date category search and reset', (
    tester,
  ) async {
    final services = createTestServices();
    final now = DateTime.utc(2026, 9, 20, 12);
    late String refuelId;
    late String expenseId;
    late String augustExpenseId;
    await tester.runAsync(() async {
      final parking = await _categoryById(services, 'cat_expense_parking');
      final insurance = await _categoryById(services, 'cat_expense_insurance');
      final vehicle = await services.vehicleService.addVehicle(
        _draft('Commuter', 64000),
      );
      final refuel = await services.refuelService.createRefuel(
        _refuelDraft(
          vehicle.id,
          eventDateTime: DateTime.utc(2026, 9, 4, 8),
          odometer: 64100,
        ),
      );
      refuelId = refuel.id;
      final expense = await services.expenseService.createExpense(
        ExpenseDraft(
          vehicleId: vehicle.id,
          categoryId: parking.id,
          eventDateTime: DateTime.utc(2026, 9, 5, 8),
          amountMinor: 1200,
          merchant: 'Station Car Park',
          notes: 'airport run',
        ),
      );
      expenseId = expense.id;
      final augustExpense = await services.expenseService.createExpense(
        ExpenseDraft(
          vehicleId: vehicle.id,
          categoryId: insurance.id,
          eventDateTime: DateTime.utc(2026, 8, 5, 8),
          amountMinor: 30000,
          merchant: 'Policy Co',
        ),
      );
      augustExpenseId = augustExpense.id;
    });

    await _pumpApp(
      tester,
      services,
      find.byKey(const Key('mainActionButton')),
      now: now,
    );
    await _openHistoryScreen(tester);
    await _pumpUntilFound(
      tester,
      find.byKey(Key('historyActivity_refuel_$refuelId')),
    );

    await _tapAndPump(
      tester,
      find.descendant(
        of: find.byKey(const Key('historyFilterField')),
        matching: find.text('Expense'),
      ),
    );
    await _tapAndPump(
      tester,
      find.byKey(const Key('historyCustomRangeButton')),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('historyCustomRangePicker')),
    );
    await _selectDatePickerRange(tester, startDay: 5, endDay: 5);
    await _pumpUntilFound(tester, find.text('5 Sep 2026'));
    await _selectDropdownItem(
      tester,
      field: find.byKey(const Key('historyCategoryFilterField')),
      label: 'Parking',
    );
    await tester.enterText(
      find.byKey(const Key('historySearchField')),
      'airport',
    );
    await _pumpUntilFound(
      tester,
      find.byKey(Key('historyActivity_expense_$expenseId')),
    );
    await _pumpUntilGone(
      tester,
      find.byKey(Key('historyActivity_refuel_$refuelId')),
    );
    expect(
      find.byKey(Key('historyActivity_expense_$augustExpenseId')),
      findsNothing,
    );

    await _tapAndPump(
      tester,
      find.byKey(const Key('historyResetFiltersButton')),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(Key('historyActivity_refuel_$refuelId')),
    );
    expect(tester.takeException(), isNull);
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
  Finder readyFinder, {
  DateTime? now,
}) async {
  final controller = DriveTrackerController(
    database: services.database,
    clock: now == null ? null : () => now,
    attachmentStorage: ManagedAttachmentStorage(
      rootDirectory: () async => services.attachmentRoot,
    ),
    attachmentPicker: services.attachmentPicker,
    attachmentOpener: services.attachmentOpener,
  );
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

Future<void> _selectDatePickerRange(
  WidgetTester tester, {
  required int startDay,
  required int endDay,
}) async {
  await _tapDatePickerDay(tester, startDay);
  await _tapDatePickerDay(tester, endDay);
  await _tapDatePickerTextAction(tester, 'Apply');
}

Future<void> _tapInsightsCustomRangeButton(WidgetTester tester) async {
  final customRangeButton = find.byKey(const Key('insightsCustomRangeButton'));
  await _pumpUntilFound(tester, customRangeButton);
  await tester.ensureVisible(customRangeButton);
  await tester.pump();
  await _tapAndPump(tester, customRangeButton);
}

Future<void> _tapDatePickerDay(WidgetTester tester, int day) async {
  final dayFinder = find.text(day.toString()).hitTestable();
  await _pumpUntilFound(tester, dayFinder);
  await tester.tap(dayFinder.first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _tapDatePickerTextAction(WidgetTester tester, String label) async {
  final action = find.text(label).hitTestable();
  await _pumpUntilFound(tester, action);
  await tester.tap(action.first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _closeDateRangePicker(WidgetTester tester) async {
  final closeButton = find.byTooltip('Close').hitTestable();
  await _pumpUntilFound(tester, closeButton);
  await tester.tap(closeButton.first);
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

Future<void> _openDocumentsScreen(WidgetTester tester) async {
  await _tapAndPump(tester, find.text('More').last);
  await _pumpUntilFound(tester, find.byKey(const Key('moreDocumentsTile')));
  await _tapAndPump(tester, find.byKey(const Key('moreDocumentsTile')));
  await _pumpUntilFound(tester, find.byKey(const Key('documentsLoaded')));
}

Future<void> _tapBack(WidgetTester tester) async {
  final backButton = find.byTooltip('Back').hitTestable();
  await _pumpUntilFound(tester, backButton);
  await tester.tap(backButton.first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<VehicleDocument> _waitForDocumentArchived(
  WidgetTester tester,
  TestServices services,
  String documentId,
) async {
  VehicleDocument? lastDocument;
  for (var index = 0; index < 50; index += 1) {
    final document = await tester.runAsync<VehicleDocument?>(
      () => services.documents.getById(documentId),
    );
    lastDocument = document;
    if (document != null && document.isArchived) {
      return document;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  final document =
      lastDocument ?? fail('Expected document $documentId to remain stored.');
  expect(
    document.isArchived,
    isTrue,
    reason: 'Expected document to be archived.',
  );
  return document;
}

Future<File> _writeAttachmentSource(TestServices services, String name) async {
  final file = File(p.join(services.attachmentRoot.parent.path, name));
  await file.parent.create(recursive: true);
  return file.writeAsBytes([1, 2, 3, 4]);
}

Finder _historyActivityRowsForType(DailyActivityType type) {
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> &&
        key.value.startsWith('historyActivity_${type.name}_');
  });
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

Future<_MaintenanceArchiveState> _waitForMaintenanceArchive(
  WidgetTester tester,
  TestServices services,
  String vehicleId,
  String itemId,
) async {
  _MaintenanceArchiveState? lastState;
  for (var index = 0; index < 50; index += 1) {
    final state = await tester.runAsync<_MaintenanceArchiveState>(
      () => _maintenanceArchiveState(services, vehicleId),
    );
    lastState = state;
    if (state != null &&
        state.activeItems.every((item) => item.id != itemId) &&
        state.allItems.any((item) => item.id == itemId && item.isArchived)) {
      return state;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }

  final state = lastState ?? fail('Expected maintenance archive state.');
  expect(
    state.activeItems.where((item) => item.id == itemId),
    isEmpty,
    reason: 'Expected archived item to be excluded from active maintenance.',
  );
  expect(
    state.allItems.where((item) => item.id == itemId && item.isArchived),
    isNotEmpty,
    reason: 'Expected archived item to remain in maintenance storage.',
  );
  return state;
}

Future<_MaintenanceArchiveState> _maintenanceArchiveState(
  TestServices services,
  String vehicleId,
) async {
  final activeItems = await services.maintenanceItems.listForVehicle(vehicleId);
  final allItems = await services.maintenanceItems.listForVehicle(
    vehicleId,
    includeArchived: true,
  );
  return _MaintenanceArchiveState(activeItems: activeItems, allItems: allItems);
}

class _MaintenanceArchiveState {
  const _MaintenanceArchiveState({
    required this.activeItems,
    required this.allItems,
  });

  final List<MaintenanceItem> activeItems;
  final List<MaintenanceItem> allItems;
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

Future<RecordCategory> _firstCategory(
  TestServices services,
  RecordCategoryType type,
) async {
  return (await services.categories.listByType(type)).first;
}

Future<RecordCategory> _categoryById(TestServices services, String id) async {
  final category = await services.categories.getById(id);
  return category ?? fail('Expected seeded category $id.');
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

RefuelDraft _refuelDraft(
  String vehicleId, {
  required DateTime eventDateTime,
  required int odometer,
  int totalCostMinor = 5000,
  int volumeMillilitres = 40000,
  int unitPriceMicrosPerLitre = 1250000,
}) {
  return RefuelDraft(
    vehicleId: vehicleId,
    eventDateTime: eventDateTime,
    odometer: odometer,
    fuelType: FuelType.petrol,
    totalCostMinor: totalCostMinor,
    volumeMillilitres: volumeMillilitres,
    unitPriceMicrosPerLitre: unitPriceMicrosPerLitre,
    isFullTank: true,
    missedPreviousRefuel: false,
  );
}
