import 'dart:io';
import 'dart:ui' as ui;

import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/app/theme/dt_theme.dart';
import 'package:drivetracker/core/calculations/analytics_date_range.dart';
import 'package:drivetracker/features/daily_records/domain/daily_activity.dart';
import 'package:drivetracker/features/daily_records/domain/expense.dart';
import 'package:drivetracker/features/daily_records/domain/income.dart';
import 'package:drivetracker/features/daily_records/domain/income_activity.dart';
import 'package:drivetracker/features/daily_records/domain/refuel.dart';
import 'package:drivetracker/features/daily_records/presentation/history_screen.dart';
import 'package:drivetracker/features/insights/presentation/insight_components.dart';
import 'package:drivetracker/features/insights/presentation/insights_screen.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/test_services.dart';
import 'insights_v2_widget_test.dart' show draft, openSection, waitInsights;

const _capture = String.fromEnvironment('VEHNORA_INSIGHTS_CAPTURE');
final _boundary = GlobalKey();
final _now = DateTime(2026, 9, 20, 12);

Widget _host(DriveTrackerController controller, bool dark, double scale) =>
    ChangeNotifierProvider<DriveTrackerController>.value(
      value: controller,
      child: RepaintBoundary(
        key: _boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? DTTheme.dark() : DTTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: const InsightsScreen(),
        ),
      ),
    );

Future<DriveTrackerController> _seed(WidgetTester t) async {
  final services = createTestServices();
  await t.runAsync(() async {
    final v = await services.vehicleService.addVehicle(draft);
    await services.vehicleService.addVehicle(
      const VehicleDraft(
        name: 'Car B',
        make: 'Honda',
        model: 'Civic',
        fuelType: FuelType.petrol,
        distanceUnit: DistanceUnit.miles,
        currentOdometer: 1000,
      ),
    );
    await services.expenseService.createExpense(
      ExpenseDraft(
        vehicleId: v.id,
        categoryId: 'cat_expense_parking',
        eventDateTime: _now,
        amountMinor: 2400,
      ),
    );
    for (final (date, odometer) in [
      (DateTime(2026, 8, 1), 1000),
      (_now, 1400),
    ]) {
      await services.refuelService.createRefuel(
        RefuelDraft(
          vehicleId: v.id,
          eventDateTime: date,
          odometer: odometer,
          fuelType: FuelType.petrol,
          totalCostMinor: 6000,
          volumeMillilitres: 40000,
          unitPriceMicrosPerLitre: 1500000,
          isFullTank: true,
          missedPreviousRefuel: false,
          station: 'Local station',
        ),
      );
    }
    await services.incomeService.createIncome(
      IncomeDraft(
        vehicleId: v.id,
        categoryId: 'cat_income_delivery',
        eventDateTime: _now,
        amountMinor: 12000,
        activity: IncomeActivity(
          type: IncomeActivityType.delivery,
          baseMinor: 10000,
          tipsMinor: 1000,
          travelMinor: 1000,
          otherMinor: 0,
          distanceMm: ActivityDistance.parse('40', DistanceUnit.miles),
          durationMinutes: 120,
          deliveryCount: 8,
        ),
      ),
    );
  });
  final controller = DriveTrackerController(
    database: services.database,
    clock: () => _now,
  );
  await t.runAsync(controller.initialize);
  // Seeding a second vehicle must not alter the explicit test scope.
  await t.runAsync(
    () => controller.selectVehicle(
      controller.activeVehicles.firstWhere((v) => v.name == 'Car A').id,
    ),
  );
  return controller;
}

Future<void> _finishHistoryQueries(WidgetTester t) async {
  // At large text the lazy results sliver starts below the viewport.
  await t.drag(find.byKey(const Key('historyList')), const Offset(0, -500));
  await t.pump();
  await waitInsights(t, find.byKey(const Key('historyLoaded')));
  await t.pumpAndSettle();
}

Future<void> _capturePage(WidgetTester t, String name) async {
  if (_capture.isEmpty) {
    return;
  }
  await t.pumpAndSettle();
  await t.runAsync(() async {
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_capture).create(recursive: true);
    await File('$_capture/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    const fonts = String.fromEnvironment('VEHNORA_TEST_FONT_DIR');
    if (fonts.isEmpty) {
      return;
    }
    final roboto = FontLoader('Roboto');
    for (final file in [
      'roboto-regular.ttf',
      'roboto-medium.ttf',
      'roboto-bold.ttf',
    ]) {
      roboto.addFont(
        File('$fonts/$file').readAsBytes().then((b) => ByteData.sublistView(b)),
      );
    }
    await roboto.load();
    await (FontLoader('MaterialIcons')..addFont(
          File('$fonts/materialicons-regular.otf')
              .readAsBytes()
              .then((b) => ByteData.sublistView(b)),
        ))
        .load();
  });
  testWidgets(
    'vehicle and period survive detail navigation and exact History scope',
    (t) async {
      final c = await _seed(t);
      await t.pumpWidget(_host(c, false, 1));
      await waitInsights(t, find.byKey(const Key('insightsTotalSpendMetric')));
      await t.tap(find.byKey(const Key('insightsVehicleSelector')));
      await t.pumpAndSettle();
      await t.tap(find.text('All active vehicles').last);
      await waitInsights(t, find.byKey(const Key('insightsTotalSpendMetric')));
      await t.tap(find.text('Last 3 months'));
      await waitInsights(t, find.byKey(const Key('insightsTotalSpendMetric')));
      await openSection(t, 'Fuel');
      expect(find.text('All active vehicles · Last 3 months'), findsOneWidget);
      await t.ensureVisible(find.text('Economy'));
      await t.pumpAndSettle();
      await t.tap(find.text('Economy'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Select one vehicle for measured economy'),
        findsOneWidget,
      );
      await t.ensureVisible(find.widgetWithText(TextButton, 'View all'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, 'View all'));
      await waitInsights(t, find.byType(HistoryScreen));
      await _finishHistoryQueries(t);
      final filter = t
          .widget<HistoryScreen>(find.byType(HistoryScreen))
          .initialFilter!;
      expect(filter.vehicleId, isNull);
      expect(
        filter.vehicleIds,
        unorderedEquals(c.activeVehicles.map((v) => v.id)),
      );
      expect(filter.range.preset, AnalyticsRangePreset.lastThreeMonths);
      await t.tap(find.byType(BackButton).hitTestable().last);
      await t.pumpAndSettle();
      await t.tap(find.byType(BackButton).hitTestable().last);
      await t.pumpAndSettle();
      await t.drag(
        find.byKey(const Key('insightsScreenList')),
        const Offset(0, 5000),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('insightsVehicleSelector')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'Last 3 months'),
            )
            .selected,
        isTrue,
      );
      expect(
        t
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const Key('insightsVehicleSelector')),
            )
            .initialValue,
        '__all__',
      );
      await t.tap(find.byKey(const Key('insightsVehicleSelector')));
      await t.pumpAndSettle();
      await t.tap(find.text('Car B').last);
      await waitInsights(t, find.text('No records in this range'));
      await openSection(t, 'Earnings');
      expect(find.text('Car B · Last 3 months'), findsOneWidget);
      expect(
        find.textContaining('No income activities match this filter'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('earningsDistanceRate')), findsNothing);
      await openSection(t, 'Costs');
      expect(find.text('No recorded costs in this range.'), findsOneWidget);
      await openSection(t, 'Fuel');
      expect(find.text('Not enough eligible data'), findsOneWidget);
      expect(find.text('No fills recorded in this range.'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('no vehicles has a useful empty state', (t) async {
    final s = createTestServices();
    final c = DriveTrackerController(database: s.database);
    await t.runAsync(c.initialize);
    await t.pumpWidget(_host(c, false, 1));
    expect(find.text('No active vehicles'), findsOneWidget);
    expect(find.byType(InsightNavigationCard), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('metrics expose labels and values and reflow at large text', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final semantics = t.ensureSemantics();
    try {
      await t.pumpWidget(
        MaterialApp(
          theme: DTTheme.dark(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: InsightMetricGrid(
                    tiles: [
                      InsightMetricTile(
                        label: 'Recorded operating spend',
                        value: '£123456789.00',
                        icon: Icons.payments,
                      ),
                      InsightMetricTile(
                        label: 'Driving-activity gross',
                        value: '£120.00',
                        icon: Icons.trending_up,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(
          RegExp('Recorded operating spend.*£123456789.00', dotAll: true),
        ),
        findsOneWidget,
      );
      final tiles = find.byType(InsightMetricTile);
      expect(
        t.getTopLeft(tiles.at(1)).dy,
        greaterThan(t.getBottomLeft(tiles.at(0)).dy),
      );
      expect(t.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  for (final (dark, scale, width) in [
    (false, 1.0, 393.0),
    (true, 1.8, 320.0),
  ]) {
    testWidgets(
      'dashboard and dedicated details retain scope, readable at $width / $scale / dark=$dark',
      (t) async {
        await t.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final c = await _seed(t);
        await t.pumpWidget(_host(c, dark, scale));
        await waitInsights(
          t,
          find.byKey(const Key('insightsTotalSpendMetric')),
        );
        expect(find.byType(InsightNavigationCard), findsNWidgets(3));
        expect(find.byKey(const Key('insightsBreakdown')), findsNothing);
        expect(find.byType(ExpansionTile), findsNothing);
        await _capturePage(t, 'landing-$dark');
        await openSection(t, 'Costs');
        expect(find.text('Car A · This month'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('insightsCostsTotalMetric')),
            matching: find.text('£84.00'),
          ),
          findsOneWidget,
        );
        await _capturePage(t, 'costs-$dark');
        await openSection(t, 'Fuel');
        expect(find.text('Car A · This month'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('insightsFuelPriceMetric')),
            matching: find.text('150.00 p/L'),
          ),
          findsOneWidget,
        );
        await _capturePage(t, 'fuel-$dark');
        await t.ensureVisible(find.text('Economy'));
        await t.pumpAndSettle();
        await t.tap(find.text('Economy'));
        await t.pumpAndSettle();
        expect(
          find.byKey(const Key('insightsFuelEconomyChart')),
          findsOneWidget,
        );
        await t.ensureVisible(find.text('Recent fills'));
        await t.pumpAndSettle();
        await waitInsights(t, find.textContaining('Local station'));
        final viewAll = find.widgetWithText(TextButton, 'View all');
        await t.ensureVisible(viewAll);
        await t.pumpAndSettle();
        await t.tap(viewAll);
        await waitInsights(t, find.byType(HistoryScreen));
        await _finishHistoryQueries(t);
        final filter = t
            .widget<HistoryScreen>(find.byType(HistoryScreen))
            .initialFilter!;
        expect(filter.type, DailyActivityType.refuel);
        expect(filter.vehicleId, c.selectedVehicle!.id);
        expect(filter.range.preset, AnalyticsRangePreset.month);
        await t.tap(find.byType(BackButton).hitTestable().last);
        await t.pumpAndSettle();
        await openSection(t, 'Earnings');
        expect(find.text('Car A · This month'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('earningsNetMetric')),
            matching: find.text('Not available'),
          ),
          findsOneWidget,
        );
        expect(
          find.text('Direct costs are complete for 0 of 1 activities.'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('earningsDistanceRate')), findsOneWidget);
        expect(find.textContaining('· Net £'), findsNothing);
        await _capturePage(t, 'earnings-$dark');
        await t.ensureVisible(find.text('Recent activities'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.widgetWithText(TextButton, 'View all'));
        await t.pumpAndSettle();
        await t.tap(find.widgetWithText(TextButton, 'View all'));
        await waitInsights(t, find.byType(HistoryScreen));
        await _finishHistoryQueries(t);
        final incomeFilter = t
            .widget<HistoryScreen>(find.byType(HistoryScreen))
            .initialFilter!;
        expect(incomeFilter.type, DailyActivityType.income);
        expect(incomeFilter.activityTypes, {
          IncomeActivityType.rideshare,
          IncomeActivityType.delivery,
        });
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }

  testWidgets(
    'year chart fits all twelve zero/nonzero buckets and exposes period totals',
    (t) async {
      await t.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final c = await _seed(t);
      final semantics = t.ensureSemantics();
      try {
        await t.pumpWidget(_host(c, false, 1));
        await waitInsights(
          t,
          find.byKey(const Key('insightsTotalSpendMetric')),
        );
        await t.tap(find.text('This year'));
        await waitInsights(
          t,
          find.byKey(const Key('insightsTotalSpendMetric')),
        );
        await openSection(t, 'Costs');
        await t.ensureVisible(find.byKey(const Key('insightsSpendingChart')));
        await t.pumpAndSettle();
        final viewport = t.getRect(
          find.byKey(const Key('insightsSpendingBucketViewport')),
        );
        for (var i = 0; i < 12; i++) {
          final bar = t.getRect(find.byKey(Key('insightsSpendingBucket_$i')));
          expect(bar.left, greaterThanOrEqualTo(viewport.left));
          expect(bar.right, lessThanOrEqualTo(viewport.right + .01));
        }
        expect(
          t
              .widget<SizedBox>(
                find.byKey(const Key('insightsSpendingBucketBar_0')),
              )
              .height,
          0,
        );
        expect(find.bySemanticsLabel(RegExp('Dec 2026: Fuel')), findsOneWidget);
        await t.ensureVisible(find.text('Period totals'));
        await t.pumpAndSettle();
        await t.tap(find.text('Period totals'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Dec 2026 · £0.00'));
        await t.pumpAndSettle();
        await t.tap(find.text('Dec 2026 · £0.00'));
        await t.pumpAndSettle();
        expect(
          find.byKey(const Key('insightsSelectedSpendingBucket')),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
      } finally {
        semantics.dispose();
        await t.pumpWidget(const SizedBox());
        c.dispose();
      }
    },
  );
}
