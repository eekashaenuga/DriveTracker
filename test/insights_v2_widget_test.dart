import 'package:drivetracker/features/insights/presentation/insight_visuals.dart';
import 'package:drivetracker/features/daily_records/domain/income.dart';
import 'package:drivetracker/features/daily_records/domain/income_activity.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/app/theme/dt_theme.dart';
import 'package:drivetracker/core/calculations/analytics_date_range.dart';
import 'package:drivetracker/features/insights/domain/vehicle_insights.dart';
import 'package:drivetracker/features/insights/presentation/insights_screen.dart';
import 'package:drivetracker/features/daily_records/domain/expense.dart';
import 'package:drivetracker/features/daily_records/presentation/history_screen.dart';
import 'package:drivetracker/features/daily_records/domain/daily_activity.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';

import 'helpers/test_services.dart';

class QueryController extends DriveTrackerController {
  QueryController({required super.database});
  bool fail = false;
  Completer<VehicleInsights>? blocked;
  @override
  Future<VehicleInsights> insightsFor({
    required String? vehicleId,
    required AnalyticsDateRange range,
  }) {
    if (fail) return Future.error(StateError('controlled query failure'));
    return blocked?.future ??
        super.insightsFor(vehicleId: vehicleId, range: range);
  }
}

Future<void> waitInsights(WidgetTester t, Finder f) async {
  for (var j = 0; j < 180; j++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 30));
    if (f.evaluate().isNotEmpty) return;
  }
  expect(f, findsWidgets);
}

Future<void> openSection(WidgetTester t, String title) async {
  if (find
      .byKey(Key('insightsDetail_${title.toLowerCase()}'))
      .evaluate()
      .isNotEmpty) {
    return;
  }
  if (find.byKey(const Key('insightsDetailContext')).evaluate().isNotEmpty) {
    await t.tap(find.byType(BackButton).hitTestable().last);
    await t.pumpAndSettle();
  }
  final card = find.byKey(Key('insights${title}Section'));
  await t.ensureVisible(card);
  await t.pumpAndSettle();
  await t.tap(card);
  await t.pump(const Duration(milliseconds: 350));
  await waitInsights(t, find.byKey(const Key('insightsDetailContext')));
  for (var i = 0; i < 180; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 30));
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await t.pumpAndSettle();
}

const draft = VehicleDraft(
  name: 'Car A',
  make: 'Ford',
  model: 'Focus',
  fuelType: FuelType.petrol,
  distanceUnit: DistanceUnit.miles,
  currentOdometer: 1000,
);
Widget host(QueryController c, {bool dark = false, bool large = false}) =>
    ChangeNotifierProvider<DriveTrackerController>.value(
      value: c,
      child: MaterialApp(
        theme: dark ? DTTheme.dark() : DTTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(large ? 1.8 : 1),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: const InsightsScreen(),
      ),
    );
void main() {
  testWidgets(
    'stacked cost chart exposes component totals without colour alone',
    (t) async {
      final handle = t.ensureSemantics();
      try {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DTInsightBarChart(
                bars: [
                  DTInsightBarDatum(
                    index: 0,
                    label: 'Jan',
                    value: 600,
                    valueLabel: '£6.00',
                    semanticsLabel: 'Jan: Fuel £1.00, Service £2.00, Expenses £3.00; total £6.00',
                    color: Colors.teal,
                    components: [
                      (value: 100, color: Colors.teal),
                      (value: 200, color: Colors.orange),
                      (value: 300, color: Colors.green),
                    ],
                    selected: false,
                    onTap: () {},
                  ),
                ],
                maxValue: 600,
                barKeyPrefix: 'qaBar',
              ),
            ),
          ),
        );
        expect(
          find.bySemanticsLabel(RegExp('Jan: Fuel £1.00, Service')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('qaBarBar_0')), findsOneWidget);
      } finally {
        handle.dispose();
      }
    },
  );
  testWidgets('earnings activity choice survives a range reload', (t) async {
    final s = createTestServices();
    await t.runAsync(() async {
      final v = await s.vehicleService.addVehicle(draft);
      await s.incomeService.createIncome(
        IncomeDraft(
          vehicleId: v.id,
          categoryId: 'cat_income_delivery',
          eventDateTime: DateTime.now(),
          amountMinor: 10000,
          activity: const IncomeActivity(type: IncomeActivityType.delivery),
        ),
      );
    });
    final c = QueryController(database: s.database);
    await t.runAsync(c.initialize);
    await t.pumpWidget(host(c));
    await waitInsights(t, find.byKey(const Key('insightsTotalSpendMetric')));
    await openSection(t, 'Earnings');
    final filter = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          w.decoration.labelText == 'Activity filter',
    );
    await t.ensureVisible(filter);
    await t.pumpAndSettle();
    await t.tap(filter);
    await t.pump(const Duration(milliseconds: 350));
    await t.tap(find.text('All income types').last);
    await t.pumpAndSettle();
    await t.tap(find.byType(BackButton).hitTestable().last);
    await t.pumpAndSettle();
    await t.drag(
      find.byKey(const Key('insightsScreenList')),
      const Offset(0, 5000),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Last month'));
    await t.pumpAndSettle();
    await t.tap(find.text('Last month'));
    await waitInsights(t, find.text('No records in this range'));
    if (filter.evaluate().isEmpty) await openSection(t, 'Earnings');
    expect(
      t.widget<DropdownButtonFormField<String>>(filter).initialValue,
      'all',
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets(
    'query failure offers Retry and resolves to a useful empty state',
    (t) async {
      final s = createTestServices();
      await t.runAsync(() => s.vehicleService.addVehicle(draft));
      final c = QueryController(database: s.database);
      await t.runAsync(c.initialize);
      c.fail = true;
      await t.pumpWidget(host(c));
      await waitInsights(t, find.text('Could not load Insights'));
      expect(find.byKey(const Key('insightsLoading')), findsNothing);
      c.fail = false;
      await t.tap(find.byKey(const Key('insightsRetry')));
      await waitInsights(t, find.text('No records in this range'));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  for (final changeVehicle in [false, true]) {
    testWidgets(
      'range/vehicle refresh hides stale results changeVehicle=$changeVehicle',
      (t) async {
        final s = createTestServices();
        await t.runAsync(() async {
          await s.vehicleService.addVehicle(draft);
          if (changeVehicle) {
            await s.vehicleService.addVehicle(
              const VehicleDraft(
                name: 'Car B',
                make: 'Honda',
                model: 'Civic',
                fuelType: FuelType.petrol,
                distanceUnit: DistanceUnit.kilometers,
                currentOdometer: 2000,
              ),
            );
          }
        });
        final c = QueryController(database: s.database);
        await t.runAsync(c.initialize);
        await t.pumpWidget(host(c));
        await waitInsights(
          t,
          find.byKey(const Key('insightsTotalSpendMetric')),
        );
        c.blocked = Completer<VehicleInsights>();
        if (changeVehicle) {
          await t.tap(find.byKey(const Key('insightsVehicleSelector')));
          await t.pump(const Duration(milliseconds: 350));
          await t.tap(find.text('Car A').last);
        } else {
          await t.tap(find.text('Last month'));
        }
        await t.pump();
        expect(find.byKey(const Key('insightsLoading')), findsOneWidget);
        expect(find.byKey(const Key('insightsTotalSpendMetric')), findsNothing);
        final result = await t.runAsync(
          () => s.insights.loadInsights(
            vehicleId: c.selectedVehicle!.id,
            range: const AnalyticsDateRange.preset(
              AnalyticsRangePreset.lastMonth,
            ),
          ),
        );
        c.blocked!.complete(result);
        await waitInsights(
          t,
          find.byKey(const Key('insightsTotalSpendMetric')),
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
  for (final dark in [false, true]) {
    testWidgets(
      'dedicated details, accessible costs and sparse fuel at large text dark=$dark',
      (t) async {
        await t.binding.setSurfaceSize(const Size(320, 900));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final s = createTestServices();
        await t.runAsync(() async {
          final v = await s.vehicleService.addVehicle(draft);
          await s.expenseService.createExpense(
            ExpenseDraft(
              vehicleId: v.id,
              categoryId: 'cat_expense_parking',
              eventDateTime: DateTime.now(),
              amountMinor: 12345,
            ),
          );
        });
        final c = QueryController(database: s.database);
        await t.runAsync(c.initialize);
        await t.pumpWidget(host(c, dark: dark, large: true));
        await waitInsights(
          t,
          find.byKey(const Key('insightsTotalSpendMetric')),
        );
        expect(find.text('Net result'), findsNothing);
        expect(find.byType(ExpansionTile), findsNothing);
        await openSection(t, 'Costs');
        await t.scrollUntilVisible(
          find.byKey(const Key('insightsBreakdown_cat_expense_parking')),
          350,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        await t.tap(
          find.byKey(const Key('insightsBreakdown_cat_expense_parking')),
        );
        await t.pump();
        await t.ensureVisible(
          find.byKey(const Key('insightsBreakdownDrilldownButton')),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('insightsBreakdownDrilldownButton')));
        await waitInsights(t, find.byType(HistoryScreen));
        final filter = t
            .widget<HistoryScreen>(find.byType(HistoryScreen))
            .initialFilter!;
        expect(filter.operatingCostsOnly, isTrue);
        expect(filter.type, DailyActivityType.expense);
        expect(filter.categoryId, 'cat_expense_parking');
        await t.tap(find.byType(BackButton).hitTestable().last);
        await t.pumpAndSettle();
        await openSection(t, 'Fuel');
        await t.scrollUntilVisible(
          find.text('Price').last,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Not enough data for this fuel trend.'), findsWidgets);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
}
