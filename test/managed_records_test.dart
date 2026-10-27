import 'dart:io';

import 'package:drivetracker/features/data_safety/domain/data_safety_service.dart';
import 'package:drivetracker/features/attachments/domain/attachment_io.dart';

import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/app/theme/dt_theme.dart';
import 'package:drivetracker/core/database/database_migrations.dart';
import 'package:drivetracker/core/utilities/validation_exception.dart';
import 'package:drivetracker/features/daily_records/domain/daily_activity.dart';
import 'package:drivetracker/features/daily_records/domain/expense.dart';
import 'package:drivetracker/features/daily_records/domain/income.dart';
import 'package:drivetracker/features/daily_records/domain/refuel.dart';
import 'package:drivetracker/features/daily_records/domain/record_category.dart';
import 'package:drivetracker/features/daily_records/presentation/history_screen.dart';
import 'package:drivetracker/features/daily_records/presentation/managed_categories_screen.dart';
import 'package:drivetracker/features/daily_records/presentation/expense_form_screen.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_item.dart';
import 'package:drivetracker/features/maintenance/domain/service_record.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/test_services.dart';

final _date = DateTime.utc(2026, 10, 1, 12);
const _draft = VehicleDraft(
  name: 'Test vehicle with a long descriptive name',
  make: 'Ford',
  model: 'Fiesta',
  fuelType: FuelType.petrol,
  distanceUnit: DistanceUnit.miles,
  currentOdometer: 1000,
);

void main() {
  for (final type in [RecordCategoryType.expense, RecordCategoryType.income]) {
    test(
      '${type.name} lifecycle, ordering and safe deletion preserve historical references',
      () async {
        final s = createTestServices();
        final v = await s.vehicleService.addVehicle(_draft);
        final category = await s.categoryService.createCustomCategory(
          type: type,
          name: 'Custom',
        );
        final second = await s.categoryService.createCustomCategory(
          type: type,
          name: 'Second',
        );
        String id;
        if (type == RecordCategoryType.expense) {
          id = (await s.expenseService.createExpense(
            ExpenseDraft(
              vehicleId: v.id,
              categoryId: category.id,
              eventDateTime: _date,
              amountMinor: 1000,
            ),
          )).id;
        } else {
          id = (await s.incomeService.createIncome(
            IncomeDraft(
              vehicleId: v.id,
              categoryId: category.id,
              eventDateTime: _date,
              amountMinor: 1000,
            ),
          )).id;
        }
        await s.categoryService.rename(category.id, 'Renamed');
        expect((await s.categories.getById(category.id))!.name, 'Renamed');
        final active = await s.categories.listByType(type);
        final ids = active.map((c) => c.id).toList().reversed.toList();
        await s.categoryService.reorder(type, ids);
        expect((await s.categories.listByType(type)).map((c) => c.id), ids);
        await s.categoryService.setArchived(category.id, true);
        expect(
          (await s.categories.listByType(type)).map((c) => c.id),
          isNot(contains(category.id)),
        );
        expect((await s.categories.getById(category.id))!.isArchived, isTrue);
        await expectLater(
          s.categoryService.delete(category.id),
          throwsA(isA<ValidationException>()),
        );
        if (type == RecordCategoryType.expense) {
          await s.expenseService.updateExpense(
            id,
            ExpenseDraft(
              vehicleId: v.id,
              categoryId: category.id,
              eventDateTime: _date,
              amountMinor: 2000,
            ),
          );
          expect((await s.expenses.getById(id))!.categoryId, category.id);
          await expectLater(
            s.expenseService.createExpense(
              ExpenseDraft(
                vehicleId: v.id,
                categoryId: category.id,
                eventDateTime: _date,
                amountMinor: 1000,
              ),
            ),
            throwsA(isA<ValidationException>()),
          );
        } else {
          await s.incomeService.updateIncome(
            id,
            IncomeDraft(
              vehicleId: v.id,
              categoryId: category.id,
              eventDateTime: _date,
              amountMinor: 2000,
            ),
          );
          expect((await s.incomes.getById(id))!.categoryId, category.id);
          await expectLater(
            s.incomeService.createIncome(
              IncomeDraft(
                vehicleId: v.id,
                categoryId: category.id,
                eventDateTime: _date,
                amountMinor: 1000,
              ),
            ),
            throwsA(isA<ValidationException>()),
          );
        }
        await s.database.close();
        expect((await s.categories.getById(category.id))!.name, 'Renamed');
        await s.categoryService.setArchived(category.id, false);
        expect(
          (await s.categories.listByType(type)).map((c) => c.id),
          contains(category.id),
        );
        await s.categoryService.delete(second.id);
        expect(await s.categories.getById(second.id), isNull);
        expect(DatabaseMigrations.schemaVersion, 6);
      },
    );
  }

  test(
    'system categories are protected and stale/cross-type reorder is atomic',
    () async {
      final s = createTestServices();
      final values = await s.categories.listByType(RecordCategoryType.expense);
      final system = values.firstWhere((c) => c.systemCategory);
      for (final action in [
        () => s.categoryService.rename(system.id, 'Bad'),
        () => s.categoryService.setArchived(system.id, true),
        () => s.categoryService.delete(system.id),
      ]) {
        await expectLater(action(), throwsA(isA<ValidationException>()));
      }
      await expectLater(
        s.categoryService.reorder(RecordCategoryType.expense, [system.id]),
        throwsA(isA<ValidationException>()),
      );
      expect(
        (await s.categories.listByType(RecordCategoryType.expense))
            .map((c) => c.id),
        values.map((c) => c.id),
      );
    },
  );

  test(
    'archived names remain reserved and concurrent creation is serialized',
    () async {
      final s = createTestServices();
      final c = await s.categoryService.createCustomCategory(
        type: RecordCategoryType.expense,
        name: 'Reserved',
      );
      await s.categoryService.setArchived(c.id, true);
      final other = await s.categoryService.createCustomCategory(
        type: RecordCategoryType.expense,
        name: 'Other custom',
      );
      await expectLater(
        s.categoryService.rename(other.id, ' reserved '),
        throwsA(isA<ValidationException>()),
      );
      final results = await Future.wait([
        for (var i = 0; i < 2; i++)
          s.categoryService
              .createCustomCategory(
                type: RecordCategoryType.income,
                name: 'Same',
              )
              .then<Object>((v) => v)
              .catchError((Object e) => e),
      ]);
      expect(results.whereType<RecordCategory>(), hasLength(1));
      expect(results.whereType<ValidationException>(), hasLength(1));
    },
  );

  test('V1 backup restores archived referenced categories and ordering without schema changes', () async {
    final source = createTestServices();
    final v = await source.vehicleService.addVehicle(_draft);
    final category = await source.categoryService.createCustomCategory(
      type: RecordCategoryType.expense,
      name: 'Backup category',
    );
    final expense = await source.expenseService.createExpense(
      ExpenseDraft(
        vehicleId: v.id,
        categoryId: category.id,
        eventDateTime: _date,
        amountMinor: 1200,
      ),
    );
    final order = (await source.categories.listByType(
      RecordCategoryType.expense,
    )).map((c) => c.id).toList().reversed.toList();
    await source.categoryService.reorder(RecordCategoryType.expense, order);
    await source.categoryService.setArchived(category.id, true);
    final dir = await Directory.systemTemp.createTemp(
      'managed_category_backup_',
    );
    addTearDown(() => dir.delete(recursive: true));
    DataSafetyService safety(TestServices s) => DataSafetyService(
      database: s.database,
      attachmentStorage: ManagedAttachmentStorage(
        rootDirectory: () async => s.attachmentRoot,
      ),
    );
    final backup = await safety(source).createBackup(outputDirectory: dir);
    final target = createTestServices();
    await safety(target).restoreBackupFromFile(backup.file.path);
    expect((await target.categories.getById(category.id))!.isArchived, isTrue);
    expect(
      (await target.expenses.getById(expense.id))!.categoryId,
      category.id,
    );
    expect(
      (await target.categories.listByType(
        RecordCategoryType.expense,
        includeArchived: true,
      )).map((c) => c.id),
      order,
    );
    expect(DatabaseMigrations.schemaVersion, 6);
    expect(DataSafetyService.backupFormatVersion, 1);
  });

  testWidgets(
    'category manager supports add rename reorder archive restore and safe delete',
    (tester) async {
      final s = createTestServices();
      late String usedId;
      await tester.runAsync(() async {
        final v = await s.vehicleService.addVehicle(_draft);
        final c = await s.categoryService.createCustomCategory(
          type: RecordCategoryType.expense,
          name: 'Used category',
        );
        usedId = c.id;
        await s.expenseService.createExpense(
          ExpenseDraft(
            vehicleId: v.id,
            categoryId: c.id,
            eventDateTime: _date,
            amountMinor: 1000,
          ),
        );
      });
      final controller = DriveTrackerController(database: s.database);
      addTearDown(controller.dispose);
      await tester.runAsync(controller.initialize);
      await _pump(
        tester,
        controller,
        const ManagedCategoriesScreen(),
        dark: true,
        scale: 2,
      );
      await _findCategory(
        tester,
        find.widgetWithText(ListTile, 'Used category'),
      );
      await _findCategory(
        tester,
        find.widgetWithText(ListTile, 'Used category'),
      );
      await _tap(tester, find.byTooltip('Actions for Used category'));
      await _tap(tester, find.text('Delete').last);
      await _until(tester, find.byType(AlertDialog));
      await tester.pumpAndSettle();
      await _tap(tester, find.widgetWithText(FilledButton, 'Delete'));
      await _until(tester, find.textContaining('Archive it instead.'));
      expect(
        await tester.runAsync(() => s.categories.getById(usedId)),
        isNotNull,
      );
      await _findCategory(
        tester,
        find.widgetWithText(ListTile, 'Used category'),
      );
      await _tap(tester, find.byTooltip('Actions for Used category'));
      await _tap(tester, find.text('Archive').last);
      await _untilGone(tester, find.text('Used category'));
      await _tap(tester, find.byType(Switch));
      await _findCategory(
        tester,
        find.widgetWithText(ListTile, 'Used category'),
      );
      await _findCategory(
        tester,
        find.widgetWithText(ListTile, 'Used category'),
      );
      await _tap(tester, find.byTooltip('Actions for Used category'));
      await _tap(tester, find.text('Restore').last);
      await _untilGone(tester, find.text('Used category'));
      await _tap(tester, find.byType(Switch));
      await _findCategory(
        tester,
        find.widgetWithText(ListTile, 'Used category'),
      );
      await _tap(tester, find.byTooltip('Add category'));
      await tester.enterText(
        find.byKey(const Key('categoryNameField')),
        'New managed',
      );
      await _tap(tester, find.byKey(const Key('addCategoryButton')));
      await _untilGone(tester, find.byKey(const Key('categoryNameField')));
      await _findCategory(tester, find.widgetWithText(ListTile, 'New managed'));
      await _tap(tester, find.byTooltip('Actions for New managed'));
      await _tap(tester, find.text('Rename').last);
      await tester.enterText(
        find.byKey(const Key('categoryNameField')),
        'Renamed managed',
      );
      await _tap(tester, find.byKey(const Key('addCategoryButton')));
      await _untilGone(tester, find.byKey(const Key('categoryNameField')));
      await _findCategory(
        tester,
        find.widgetWithText(ListTile, 'Renamed managed'),
      );
      await _tap(tester, find.byTooltip('Actions for Renamed managed'));
      await _tap(tester, find.text('Move up').last);
      await _until(tester, find.text('Order updated.'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'archived original is retained in edit selector, excluded on new expense',
    (tester) async {
      final s = createTestServices();
      late String id;
      await tester.runAsync(() async {
        final v = await s.vehicleService.addVehicle(_draft);
        final c = await s.categoryService.createCustomCategory(
          type: RecordCategoryType.expense,
          name: 'Archived original',
        );
        final r = await s.expenseService.createExpense(
          ExpenseDraft(
            vehicleId: v.id,
            categoryId: c.id,
            eventDateTime: _date,
            amountMinor: 1000,
          ),
        );
        id = r.id;
        await s.categoryService.setArchived(c.id, true);
      });
      final c = DriveTrackerController(database: s.database);
      addTearDown(c.dispose);
      await tester.runAsync(c.initialize);
      final record = await tester.runAsync(() => s.expenses.getById(id));
      await _pump(tester, c, ExpenseFormScreen(expense: record));
      await _until(tester, find.text('Archived original (archived)'));
      await _pump(tester, c, const ExpenseFormScreen(key: ValueKey('new')));
      await _until(tester, find.byKey(const Key('expenseCategoryField')));
      expect(find.text('Archived original (archived)'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final type in [
    DailyActivityType.refuel,
    DailyActivityType.expense,
    DailyActivityType.income,
    DailyActivityType.service,
    DailyActivityType.odometer,
  ]) {
    testWidgets(
      '${type.name}: History Details Edit saves same ID and refreshes Details and list',
      (tester) async {
        final s = createTestServices();
        late String id;
        late String vehicleId;
        String? maintenanceId;
        await tester.runAsync(() async {
          final v = await s.vehicleService.addVehicle(_draft);
          vehicleId = v.id;
          switch (type) {
            case DailyActivityType.refuel:
              id = (await s.refuelService.createRefuel(
                RefuelDraft(
                  vehicleId: v.id,
                  eventDateTime: _date,
                  odometer: 1100,
                  fuelType: FuelType.petrol,
                  totalCostMinor: 5000,
                  volumeMillilitres: 40000,
                  unitPriceMicrosPerLitre: 1250000,
                  isFullTank: true,
                  missedPreviousRefuel: false,
                ),
              )).id;
              break;
            case DailyActivityType.expense:
              final c = await s.categoryService.createCustomCategory(
                type: RecordCategoryType.expense,
                name: 'Historic category',
              );
              id = (await s.expenseService.createExpense(
                ExpenseDraft(
                  vehicleId: v.id,
                  categoryId: c.id,
                  eventDateTime: _date,
                  amountMinor: 1000,
                ),
              )).id;
              await s.categoryService.setArchived(c.id, true);
              break;
            case DailyActivityType.income:
              final c = (await s.categories.listByType(
                RecordCategoryType.income,
              )).first;
              id = (await s.incomeService.createIncome(
                IncomeDraft(
                  vehicleId: v.id,
                  categoryId: c.id,
                  eventDateTime: _date,
                  amountMinor: 1000,
                ),
              )).id;
              break;
            case DailyActivityType.service:
              final item = await s.maintenanceItemService.createMaintenanceItem(
                MaintenanceItemDraft(
                  vehicleId: v.id,
                  name: 'Oil change',
                  mileageInterval: 1000,
                ),
              );
              maintenanceId = item.id;
              id = (await s.serviceRecordService.createServiceRecord(
                ServiceRecordDraft(
                  vehicleId: v.id,
                  eventDateTime: _date,
                  odometer: 1100,
                  totalCostMinor: 3000,
                  items: [
                    ServiceItemDraft(
                      itemName: item.name,
                      maintenanceItemId: item.id,
                    ),
                  ],
                ),
              )).record.id;
              break;
            case DailyActivityType.odometer:
              id = (await s.odometerService.recordManualReading(
                vehicleId: v.id,
                odometer: 1100,
                eventDateTime: _date,
              )).id;
              break;
            case DailyActivityType.all:
              break;
          }
        });
        final c = DriveTrackerController(database: s.database);
        addTearDown(c.dispose);
        await tester.runAsync(c.initialize);
        await _pump(
          tester,
          c,
          const HistoryScreen(),
          dark: type == DailyActivityType.income,
          scale: type == DailyActivityType.expense ? 1.5 : 1,
        );
        final row = find.byKey(Key('historyActivity_${type.name}_$id'));
        await _until(tester, row);
        await _tap(tester, row);
        await _until(tester, find.byKey(Key('recordDetailsLoaded_$id')));
        expect(find.byType(TextFormField), findsNothing);
        if (type == DailyActivityType.expense) {
          expect(find.text('Historic category (archived)'), findsOneWidget);
        }
        final edit = find.byKey(
          Key(
            type == DailyActivityType.odometer
                ? 'historyEditOdometerButton'
                : 'recordDetailsEdit',
          ),
        );
        await _tap(tester, edit);
        final field = switch (type) {
          DailyActivityType.refuel => 'refuelTotalCostField',
          DailyActivityType.expense => 'expenseAmountField',
          DailyActivityType.income => 'incomeAmountField',
          DailyActivityType.service => 'serviceTotalCostField',
          _ => 'editOdometerReadingField',
        };
        final save = switch (type) {
          DailyActivityType.refuel => 'saveRefuelButton',
          DailyActivityType.expense => 'saveExpenseButton',
          DailyActivityType.income => 'saveIncomeButton',
          DailyActivityType.service => 'saveServiceButton',
          _ => 'saveOdometerEntryButton',
        };
        await _until(tester, find.byKey(Key(field)));
        await tester.enterText(
          find.byKey(Key(field)),
          type == DailyActivityType.odometer
              ? '1200'
              : type == DailyActivityType.refuel
              ? '60.00'
              : '20.00',
        );
        await _tap(tester, find.byKey(Key(save)));
        await _until(tester, find.byKey(Key('recordDetailsLoaded_$id')));
        final expected = type == DailyActivityType.odometer
            ? '1,200 mi'
            : type == DailyActivityType.refuel
            ? '£60.00'
            : '£20.00';
        await _until(tester, find.text(expected));
        final db = await tester.runAsync(() => s.database.database);
        final table = switch (type) {
          DailyActivityType.refuel => 'refuels',
          DailyActivityType.expense => 'expenses',
          DailyActivityType.income => 'income_records',
          DailyActivityType.service => 'services',
          _ => 'odometer_entries',
        };
        final records = await tester.runAsync(
          () => db!.query(table, where: 'id = ?', whereArgs: [id]),
        );
        expect(records, hasLength(1));
        if (type != DailyActivityType.odometer) {
          final all = await tester.runAsync(() => db!.query(table));
          expect(all, hasLength(1));
        }
        if (type == DailyActivityType.service) {
          final links = await tester.runAsync(
            () => db!.query(
              'service_items',
              where: 'maintenance_item_id = ?',
              whereArgs: [maintenanceId],
            ),
          );
          expect(links, hasLength(1));
          expect(links!.single['service_id'], id);
        }
        if (type == DailyActivityType.expense) {
          await tester.runAsync(
            () => c.addCustomCategory(
              type: RecordCategoryType.expense,
              name: 'Added while editing',
            ),
          );
        }
        await _tap(tester, find.byTooltip('Back'));
        await _until(tester, row);
        if (type == DailyActivityType.expense) {
          await _tap(
            tester,
            find.byKey(const Key('historyCategoryFilterField')),
          );
          await _until(tester, find.text('Added while editing'));
          Navigator.of(tester.element(find.text('Added while editing').last))
              .pop();
          await tester.pump(const Duration(milliseconds: 400));
        }
        expect(
          find.descendant(
            of: row,
            matching: find.textContaining(
              type == DailyActivityType.odometer
                  ? '1,200'
                  : type == DailyActivityType.refuel
                  ? '60.00'
                  : '20.00',
            ),
          ),
          findsWidgets,
        );
        expect(
          await tester.runAsync(
            () => s.odometers.currentOdometerForVehicle(vehicleId),
          ),
          type == DailyActivityType.odometer
              ? 1200
              : type == DailyActivityType.refuel ||
                    type == DailyActivityType.service
              ? 1100
              : 1000,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  DriveTrackerController c,
  Widget child, {
  bool dark = false,
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(const Size(360, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: c,
      child: MaterialApp(
        theme: dark ? DTTheme.dark() : DTTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: child,
      ),
    ),
  );
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets);
}

Future<void> _untilGone(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isEmpty) return;
  }
  expect(finder, findsNothing);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await Scrollable.ensureVisible(tester.element(finder.last), alignment: 0.5);
  await tester.pump(const Duration(milliseconds: 300));
  for (var i = 0; i < 8 && finder.last.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -120));
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(finder.last.hitTestable(), findsOneWidget);
  await tester.runAsync(() async {
    await tester.tap(finder.last);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _findCategory(WidgetTester tester, Finder finder) async {
  final list = find.byType(ReorderableListView);
  await _until(tester, list);
  if (finder.evaluate().isEmpty) {
    await tester.drag(list, const Offset(0, 2000));
    await tester.pump(const Duration(milliseconds: 200));
  }
  for (var i = 0; i < 100; i++) {
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder);
      return;
    }
    await tester.drag(list, const Offset(0, -240));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets);
}
