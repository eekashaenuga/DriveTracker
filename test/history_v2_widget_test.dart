import 'package:drivetracker/core/database/app_database.dart';
import 'package:drivetracker/features/daily_records/domain/history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/app/theme/dt_theme.dart';
import 'package:drivetracker/features/daily_records/presentation/history_screen.dart';
import 'package:drivetracker/features/daily_records/presentation/history_record_row.dart';
import 'package:drivetracker/features/daily_records/domain/history_filter.dart';
import 'package:drivetracker/features/daily_records/domain/daily_activity.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';

import 'helpers/test_services.dart';

Future<void> wait(WidgetTester t, bool Function() condition) async {
  for (var i = 0; i < 300 && !condition(); i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}

late TestServices currentServices;

Future<DriveTrackerController> setup(
  WidgetTester t, {
  bool dark = false,
  double scale = 1,
  HistoryFilter? initial,
  bool fail = false,
  bool multiple = false,
  bool emptyRecords = false,
}) async {
  final s = createTestServices();
  currentServices = s;
  await t.runAsync(() async {
    final v = await s.vehicleService.addVehicle(
      const VehicleDraft(
        name: 'Fiesta',
        make: 'Ford',
        model: 'Fiesta',
        fuelType: FuelType.petrol,
        distanceUnit: DistanceUnit.miles,
        currentOdometer: 1000,
      ),
    );
    if (multiple) {
      final archived = await s.vehicleService.addVehicle(
        const VehicleDraft(
          name: 'Archived car',
          make: 'Ford',
          model: 'Focus',
          fuelType: FuelType.petrol,
          distanceUnit: DistanceUnit.kilometers,
          currentOdometer: 1000,
        ),
      );
      final db = await s.database.database;
      final date = DateTime.utc(2026, 10, 1, 12).toIso8601String();
      await db.insert('expenses', {
        'id': 'archived',
        'vehicle_id': archived.id,
        'category_id': 'cat_expense_parking',
        'event_datetime': date,
        'amount_minor': 33,
        'merchant': 'archived-only',
        'created_at': date,
        'updated_at': date,
      });
      await s.vehicleService.archiveVehicle(archived.id);
      await s.settings.setSelectedVehicleId(v.id);
    }
    final db = await s.database.database;
    for (var i = 0; i < 64; i++) {
      final date = DateTime.utc(2026, 10, 1, 12).toIso8601String();
      await db.insert('expenses', {
        'id': 'e${i.toString().padLeft(3, '0')}',
        'vehicle_id': v.id,
        'category_id': 'cat_expense_parking',
        'event_datetime': date,
        'amount_minor': i + 1,
        'merchant': i == 0 ? '100% airport' : 'ordinary',
        'created_at': date,
        'updated_at': date,
      });
    }
  });
  if (emptyRecords) {
    await t.runAsync(() async {
      final db = await s.database.database;
      await db.delete('expenses');
      await db.delete('odometer_entries');
    });
  }
  final c = HistoryTestController(s.database)..failPage = fail;
  addTearDown(c.dispose);
  await t.runAsync(c.initialize);
  await t.pumpWidget(
    ChangeNotifierProvider<DriveTrackerController>.value(
      value: c,
      child: MaterialApp(
        theme: DTTheme.light(),
        darkTheme: DTTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: HistoryScreen(initialFilter: initial),
      ),
    ),
  );
  await wait(
    t,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
  return c;
}

class HistoryTestController extends DriveTrackerController {
  HistoryTestController(AppDatabase database) : super(database: database);
  bool failPage = false;
  @override
  Future<HistoryPage> historyPage(
    HistoryFilter filter, {
    HistoryCursor? after,
  }) {
    if (failPage) return Future.error(StateError('Controlled query failure'));
    return super.historyPage(filter, after: after);
  }
}

void main() {
  testWidgets('no vehicles is distinct from an empty vehicle history', (
    t,
  ) async {
    final s = createTestServices();
    final c = DriveTrackerController(database: s.database);
    addTearDown(c.dispose);
    await t.runAsync(c.initialize);
    await t.pumpWidget(
      ChangeNotifierProvider<DriveTrackerController>.value(
        value: c,
        child: MaterialApp(theme: DTTheme.light(), home: const HistoryScreen()),
      ),
    );
    await wait(
      t,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    expect(find.text('No active vehicles'), findsOneWidget);
    expect(find.text('No matching records'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('empty vehicle has useful unfiltered History state', (t) async {
    await setup(t, emptyRecords: true);
    expect(find.text('No history yet'), findsOneWidget);
    expect(find.text('No matching records'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'source deleted before tap shows feedback and removes stale row',
    (t) async {
      await setup(t);
      final row = find.byKey(const Key('historyActivity_expense_e063'));
      await t.ensureVisible(row);
      await t.pump();
      await t.runAsync(() async {
        final db = await currentServices.database.database;
        await db.delete('expenses', where: 'id = ?', whereArgs: ['e063']);
      });
      await t.tap(row);
      await t.pump();
      await wait(
        t,
        () => find
            .text('Could not open this record. It may have been removed.')
            .evaluate()
            .isNotEmpty,
      );
      await wait(
        t,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      await wait(t, () => row.evaluate().isEmpty);
      expect(row, findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'sort date and incompatible type changes reset paging and preserve explicit selections',
    (t) async {
      await setup(t);
      await t.tap(find.byTooltip('Sort'));
      await t.pumpAndSettle();
      await t.tap(find.text('Oldest first').last);
      await t.pump();
      await wait(
        t,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      await t.pumpAndSettle();
      expect(find.text('January 2026'), findsOneWidget);
      expect(find.text('Oldest first'), findsOneWidget);
      await t.tap(find.byKey(const Key('historyDateButton')));
      await t.pumpAndSettle();
      await t.tap(find.text('Last month').last);
      await t.pump();
      await wait(
        t,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      await t.pumpAndSettle();
      expect(find.text('Last month'), findsOneWidget);
      await t.tap(find.text('Income'));
      await t.pump();
      await wait(
        t,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      expect(find.text('No matching records'), findsOneWidget);
      await t.tap(find.byKey(const Key('historyResetFiltersButton')));
      await t.pump();
      await wait(
        t,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      expect(find.text('Oldest first'), findsNothing);
      expect(find.text('Last month'), findsNothing);
      expect(find.byType(HistoryRecordRow), findsWidgets);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'All active excludes archived and deliberate archived access restores visibility',
    (t) async {
      await setup(t, multiple: true);
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('All active vehicles').last);
      await t.pump();
      await wait(
        t,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      await t.enterText(
        find.byKey(const Key('historySearchField')),
        'archived-only',
      );
      await t.pump(const Duration(milliseconds: 350));
      await wait(
        t,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      expect(find.text('No matching records'), findsOneWidget);
      await t.tap(find.text('Filters'));
      await t.pump(const Duration(milliseconds: 350));
      await wait(
        t,
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(SwitchListTile));
      await t.pump();
      await t.tap(find.text('Apply filters'));
      await t.pump(const Duration(milliseconds: 350));
      await wait(
        t,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      expect(
        find.byKey(const Key('historyActivity_expense_archived')),
        findsOneWidget,
      );
      expect(find.textContaining('Archived car'), findsWidgets);
      expect(find.text('Archived vehicles included'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('query failure Retry recovers without losing search state', (
    t,
  ) async {
    final c = await setup(t, fail: true) as HistoryTestController;
    expect(find.text('Could not load History.'), findsOneWidget);
    c.failPage = false;
    await t.tap(find.text('Retry'));
    await t.pump();
    await wait(
      t,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    expect(find.byType(HistoryRecordRow), findsWidgets);
    expect(find.text('Could not load History.'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'row keeps baseline null separate from zero and reflows mixed units large amounts',
    (t) async {
      t.view.physicalSize = const Size(320, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final date = DateTime(2026, 10, 24, 12);
      await t.pumpWidget(
        MaterialApp(
          theme: DTTheme.dark(),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final (id, amount, unit) in [
                      ('baseline', null, DistanceUnit.miles),
                      ('zero', 0, DistanceUnit.kilometers),
                      ('large', 999999999, DistanceUnit.miles),
                    ])
                      HistoryRecordRow(
                        record: DailyActivity(
                          type: DailyActivityType.service,
                          recordId: id,
                          vehicleId: 'v',
                          eventDateTime: date,
                          createdAt: date,
                          title: id == 'baseline' ? 'Maintenance baseline' : 'Long descriptive service title with many useful words',
                          subtitle: 'Recorded metadata',
                          amountMinor: amount,
                          odometer: 60000,
                          vehicleDistanceUnit: unit,
                          vehicleName: 'Very long vehicle name',
                        ),
                        showVehicle: true,
                        onTap: () {},
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('£0.00'), findsOneWidget);
      expect(find.textContaining('£9999999.99'), findsOneWidget);
      expect(find.text('Maintenance baseline'), findsOneWidget);
      expect(find.textContaining('km'), findsWidgets);
      expect(find.textContaining('mi'), findsWidgets);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('debounced search literal clear chips and lazy paging reset', (
    t,
  ) async {
    await setup(t);
    expect(find.byType(HistoryRecordRow).evaluate().length, lessThan(50));
    await t.enterText(find.byKey(const Key('historySearchField')), '100%');
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('historyActivity_expense_e000')), findsNothing);
    await t.pump(const Duration(milliseconds: 150));
    await wait(
      t,
      () => find
          .byKey(const Key('historyActivity_expense_e000'))
          .evaluate()
          .isNotEmpty,
    );
    expect(find.byKey(const Key('historyActivity_expense_e063')), findsNothing);
    expect(find.text('October 2026'), findsOneWidget);
    await t.tap(find.byTooltip('Clear search'));
    await t.pump();
    await wait(
      t,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await t.drag(find.byKey(const Key('historyList')), const Offset(0, -5000));
    await t.pump();
    await t.scrollUntilVisible(
      find.text('Load more records'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Load more records'));
    await t.pump();
    await wait(
      t,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await t.scrollUntilVisible(
      find.byKey(const Key('historyActivity_expense_e000')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const Key('historyActivity_expense_e000')),
      findsOneWidget,
    );
    await t.pumpWidget(const SizedBox.shrink());
  });
  for (final dark in [false, true]) {
    testWidgets(
      'narrow large-text ${dark ? 'dark' : 'light'} accessible rows and no-results',
      (t) async {
        t.view.physicalSize = const Size(320, 850);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final semantics = t.ensureSemantics();

        await setup(t, dark: dark, scale: 1.8);
        expect(t.takeException(), isNull);
        await t.enterText(
          find.byKey(const Key('historySearchField')),
          'not present',
        );
        await t.pump(const Duration(milliseconds: 350));
        await wait(
          t,
          () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
        );
        await t.scrollUntilVisible(
          find.text('No matching records'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Clear filters'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      },
    );
  }
  testWidgets(
    'inherited record scope cannot be broadened and Clear all releases it',
    (t) async {
      await setup(
        t,
        initial: const HistoryFilter(
          recordTypes: {DailyActivityType.refuel},
          operatingCostsOnly: true,
        ),
      );
      expect(find.text('Insights scope'), findsOneWidget);
      expect(find.text('No matching records'), findsOneWidget);
      await t.tap(find.text('Expenses'));
      await t.pump();
      await wait(
        t,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      expect(find.byType(HistoryRecordRow), findsNothing);
      await t.tap(find.byKey(const Key('historyResetFiltersButton')));
      await t.pump();
      await wait(
        t,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      expect(find.byType(HistoryRecordRow), findsWidgets);
      expect(find.text('Insights scope'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
