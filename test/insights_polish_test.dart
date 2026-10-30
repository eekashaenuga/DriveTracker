import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/app/theme/dt_theme.dart';
import 'package:drivetracker/core/calculations/analytics_date_range.dart';
import 'package:drivetracker/core/utilities/money.dart';
import 'package:drivetracker/features/daily_records/domain/income.dart';
import 'package:drivetracker/features/daily_records/domain/income_activity.dart';
import 'package:drivetracker/features/daily_records/domain/income_earnings.dart';
import 'package:drivetracker/features/daily_records/domain/refuel.dart';
import 'package:drivetracker/features/daily_records/presentation/earnings_formatters.dart';
import 'package:drivetracker/features/insights/presentation/income_activity_earnings_panel.dart';
import 'package:drivetracker/features/insights/presentation/insight_components.dart';
import 'package:drivetracker/features/insights/presentation/insight_formatters.dart';
import 'package:drivetracker/features/insights/presentation/insight_recorded_values.dart';
import 'package:drivetracker/features/insights/presentation/insight_visuals.dart';
import 'package:drivetracker/features/insights/presentation/insights_screen.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/test_services.dart';
import 'insights_v2_widget_test.dart' show draft, openSection, waitInsights;

Widget _host(Widget child, {bool dark = false, double scale = 1}) =>
    MaterialApp(
      theme: dark ? DTTheme.dark() : DTTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(20), child: child),
        ),
      ),
    );

void main() {
  test(
    'display precision rounds scaled values without altering source precision',
    () {
      expect(InsightFormat.litres(620322), '620.32 L');
      expect(InsightFormat.litres(1005), '1.01 L');
      expect(InsightFormat.price(1651860), '165.19 p/L');
      expect(InsightFormat.price(1739170), '173.92 p/L');
      expect(InsightFormat.price(1727020), '172.70 p/L');
      expect(InsightFormat.price(1718950), '171.90 p/L');
      expect(InsightFormat.price(1500000), '150.00 p/L');
      expect(InsightFormat.economy(37.845), '37.8 UK MPG');
      expect(InsightFormat.distance(60.000), '60');
      expect(InsightFormat.distance(60.125), '60.13');
      expect(InsightFormat.distance(0), '0');
      expect(
        InsightFormat.costPerDistance(93.2, DistanceUnit.miles),
        '£0.93 / mi',
      );
      expect(earningsMoney(1186), '£11.86');
      expect(earningsMoney(463), '£4.63');
      expect(MoneyAmount.formatMinor(102469), '£1024.69');
      expect(InsightFormat.price(null), '-');
      expect(InsightFormat.litres(null), '-');
      expect(InsightFormat.economy(null), 'Not enough data');
      // Other forms/calculators keep their existing precision and helpers.
      expect(FuelNumbers.formatPencePerLitre(1739170), '173.917 p/L');
      expect(FuelNumbers.formatLitres(620322), '620.322 L');
    },
  );

  test(
    'Insights dates are UK-oriented without changing calendar boundaries',
    () {
      final start = DateTime(2026, 7, 22);
      final end = DateTime(2026, 10, 24);
      final range = AnalyticsDateRange.custom(start: start, endInclusive: end);
      final before = range.resolve(DateTime(2026, 10, 25));
      expect(InsightFormat.date(end), '24 Oct 2026');
      expect(InsightFormat.date(end, compact: true), '24 Oct');
      expect(InsightFormat.range(start, end), '22 Jul 2026 – 24 Oct 2026');
      expect(InsightFormat.customRange(range), '22 Jul 2026 – 24 Oct 2026');
      expect(
        InsightFormat.customRange(
          AnalyticsDateRange.custom(start: end, endInclusive: end),
        ),
        '24 Oct 2026',
      );
      final after = range.resolve(DateTime(2026, 10, 25));
      expect(after.startInclusive, before.startInclusive);
      expect(after.endExclusive, before.endExclusive);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'category accents are stable, muted and theme-derived dark=$dark',
      (t) async {
        const ids = [
          'cat_expense_insurance',
          'cat_expense_parts',
          'cat_expense_cleaning',
          'cat_expense_tax',
          'cat_expense_parking',
        ];
        late Map<String, Color> first;
        late Map<String, Color> reordered;
        late ColorScheme scheme;
        await t.pumpWidget(
          _host(
            Builder(
              builder: (context) {
                scheme = Theme.of(context).colorScheme;
                first = {
                  for (final id in ids) id: insightCategoryAccent(context, id),
                };
                reordered = {
                  for (final id in ids.reversed)
                    id: insightCategoryAccent(context, id),
                };
                return const Text('Categories');
              },
            ),
            dark: dark,
          ),
        );
        expect(reordered, first);
        expect(first.values.toSet().length, greaterThanOrEqualTo(3));
        expect(first.values, isNot(contains(scheme.error)));
        expect(first.values, isNot(contains(scheme.errorContainer)));
        expect(t.takeException(), isNull);
      },
    );
  }

  for (final kind in ['Price', 'Economy']) {
    for (final dark in [false, true]) {
      testWidgets(
        '$kind latest-five preview and complete accessible list dark=$dark',
        (t) async {
          await t.binding.setSurfaceSize(Size(dark ? 320 : 412, 900));
          addTearDown(() => t.binding.setSurfaceSize(null));
          final points = List.generate(14, (i) {
            final date = DateTime(2026, 10, i + 1);
            final value = kind == 'Price' ? 173.917 + i : 37.8 + i;
            final formatted = kind == 'Price'
                ? InsightFormat.price(1739170 + i * 10000)
                : InsightFormat.economy(value);
            return DTInsightLinePoint(
              date: date,
              label: InsightFormat.date(date, compact: true),
              value: value,
              valueLabel: formatted,
              detailLabel: InsightFormat.date(date),
              observationDetail: kind == 'Economy' ? '200 mi · 40.00 L' : null,
              semanticsLabel: '${InsightFormat.date(date)}: $formatted',
            );
          });
          final semantics = t.ensureSemantics();
          try {
            await t.pumpWidget(
              _host(
                InsightRecordedValues(points: points, kind: kind),
                dark: dark,
                scale: dark ? 1.8 : 1,
              ),
            );
            expect(
              find.byKey(const Key('insightsRecordedValuePreviewRow')),
              findsNothing,
            );
            await t.tap(find.text('Recorded values'));
            await t.pumpAndSettle();
            expect(
              find.byKey(const Key('insightsRecordedValuePreviewRow')),
              findsNWidgets(5),
            );
            expect(find.text('14 Oct 2026'), findsOneWidget);
            expect(find.text('10 Oct 2026'), findsOneWidget);
            expect(find.text('1 Oct 2026'), findsNothing);
            expect(
              find.bySemanticsLabel(RegExp('14 Oct 2026:')),
              findsOneWidget,
            );
            final button = find.byKey(
              const Key('insightsAllRecordedValuesButton'),
            );
            await t.ensureVisible(button);
            await t.pumpAndSettle();
            expect(t.getSize(button).height, greaterThanOrEqualTo(48));
            await t.tap(button);
            await t.pumpAndSettle();
            expect(find.text('$kind recorded values'), findsOneWidget);
            final list = t.widget<ListView>(
              find.byKey(const Key('insightsAllRecordedValuesList')),
            );
            expect(list.childrenDelegate.estimatedChildCount, 14);
            await t.scrollUntilVisible(
              find.text('1 Oct 2026'),
              300,
              scrollable: find.byType(Scrollable).last,
            );
            await t.pumpAndSettle();
            expect(find.text('1 Oct 2026'), findsOneWidget);
            expect(points.length, 14);
            expect(points.first.value, kind == 'Price' ? 173.917 : 37.8);
            expect(t.takeException(), isNull);
            await t.tap(find.byType(BackButton).hitTestable().last);
            await t.pumpAndSettle();
            expect(
              find.byKey(const Key('insightsRecordedValuePreviewRow')),
              findsNWidgets(5),
            );
          } finally {
            semantics.dispose();
            await t.pumpWidget(const SizedBox());
          }
        },
      );
    }
  }

  for (final (width, scale, dark) in [
    (900.0, 1.0, false),
    (412.0, 1.0, true),
    (320.0, 1.8, false),
    (320.0, 1.8, true),
  ]) {
    testWidgets(
      'earnings aligned regions and neutral incomplete net $width/$scale dark=$dark',
      (t) async {
        await t.binding.setSurfaceSize(Size(width, 1400));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final date = DateTime(2026, 10, 25);
        final income = Income(
          id: 'income',
          vehicleId: 'vehicle',
          categoryId: 'delivery',
          eventDateTime: date,
          amountMinor: 12000,
          createdAt: date,
          updatedAt: date,
          activity: IncomeActivity(
            type: IncomeActivityType.delivery,
            distanceMm: ActivityDistance.parse('60', DistanceUnit.miles),
            durationMinutes: 120,
            deliveryCount: 8,
          ),
        );
        final before = income.toMap();
        await t.pumpWidget(
          _host(
            IncomeActivityEarningsPanel(
              records: [IncomeEarnings(income, 0)],
              unit: DistanceUnit.miles,
            ),
            dark: dark,
            scale: scale,
          ),
        );
        final gross = find.byKey(const Key('earningsGrossMetric'));
        final linked = find.byKey(const Key('earningsLinkedMetric'));
        final net = find.byKey(const Key('earningsNetMetric'));
        if (width == 900) {
          final rects = [gross, linked, net].map(t.getRect).toList();
          expect(rects.map((r) => r.top).toSet().length, 1);
          expect(rects.map((r) => r.height).toSet().length, 1);
          final labels = [
            find.text('Gross'),
            find.text('Linked direct costs'),
            find.text('Net after linked direct costs'),
          ];
          expect(labels.map((f) => t.getTopLeft(f).dy).toSet().length, 1);
          final values = [gross, linked, net].map(
            (f) => find.descendant(of: f, matching: find.byType(Text)).last,
          );
          expect(values.map((f) => t.getTopLeft(f).dy).toSet().length, 1);
        }
        if (scale > 1) {
          expect(t.getTopLeft(linked).dy, greaterThan(t.getTopLeft(gross).dy));
          expect(t.getTopLeft(net).dy, greaterThan(t.getTopLeft(linked).dy));
        }
        final context = t.element(net);
        final c = Theme.of(context).colorScheme;
        Card card(Finder f) =>
            t.widget<Card>(find.descendant(of: f, matching: find.byType(Card)));
        expect(card(gross).color, c.primaryContainer);
        expect(card(linked).color, c.tertiaryContainer);
        expect(card(net).color, c.surfaceContainer);
        expect(
          find.descendant(of: net, matching: find.text('Not available')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: net, matching: find.text('£0.00')),
          findsNothing,
        );
        expect(find.textContaining('· Net £'), findsNothing);
        expect(income.toMap(), before);
        expect(IncomeEarnings(income, 0).netMinor, isNull);
        await t.ensureVisible(find.text('Recent activities'));
        await t.pumpAndSettle();
        expect(find.text('25 Oct 2026 · £120.00'), findsOneWidget);
        expect(find.textContaining('60 mi'), findsOneWidget);
        expect(find.textContaining('60.000 mi'), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'real Fuel Price/Economy previews keep complete observations and stored precision',
    (t) async {
      final services = createTestServices();
      final raw = <Refuel>[];
      await t.runAsync(() async {
        final v = await services.vehicleService.addVehicle(draft);
        for (var i = 0; i < 8; i++) {
          raw.add(
            await services.refuelService.createRefuel(
              RefuelDraft(
                vehicleId: v.id,
                eventDateTime: DateTime(2026, 1, i + 1, 12),
                odometer: 1000 + i * 200,
                fuelType: FuelType.petrol,
                totalCostMinor: 6957,
                volumeMillilitres: 40001,
                unitPriceMicrosPerLitre: 1739170,
                isFullTank: true,
                missedPreviousRefuel: false,
              ),
            ),
          );
        }
      });
      final c = DriveTrackerController(
        database: services.database,
        clock: () => DateTime(2026, 1, 20),
      );
      await t.runAsync(c.initialize);
      final id = c.selectedVehicle!.id;
      final before = await t.runAsync(
        () => services.insights.loadInsights(
          vehicleId: id,
          range: AnalyticsDateRange.month,
          now: DateTime(2026, 1, 20),
        ),
      );
      await t.pumpWidget(
        ChangeNotifierProvider<DriveTrackerController>.value(
          value: c,
          child: MaterialApp(
            theme: DTTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: const InsightsScreen(),
          ),
        ),
      );
      await waitInsights(t, find.byKey(const Key('insightsTotalSpendMetric')));
      await openSection(t, 'Fuel');
      expect(find.text('173.92 p/L'), findsWidgets);
      expect(find.text('320.01 L'), findsOneWidget);
      for (final (kind, count) in [('Price', 8), ('Economy', 7)]) {
        if (kind == 'Economy') {
          await t.ensureVisible(find.text('Economy'));
          await t.pumpAndSettle();
          await t.tap(find.text('Economy'));
          await t.pumpAndSettle();
        }
        await t.ensureVisible(find.text('Recorded values'));
        await t.pumpAndSettle();
        await t.tap(find.text('Recorded values'));
        await t.pumpAndSettle();
        expect(
          find.byKey(const Key('insightsRecordedValuePreviewRow')),
          findsNWidgets(5),
        );
        final all = find.byKey(const Key('insightsAllRecordedValuesButton'));
        await t.ensureVisible(all);
        await t.pumpAndSettle();
        await t.tap(all);
        await t.pumpAndSettle();
        expect(
          t
              .widget<ListView>(
                find.byKey(const Key('insightsAllRecordedValuesList')),
              )
              .childrenDelegate
              .estimatedChildCount,
          count,
        );
        await t.tap(find.byType(BackButton).hitTestable().last);
        await t.pumpAndSettle();
      }
      final after = await t.runAsync(
        () => services.insights.loadInsights(
          vehicleId: id,
          range: AnalyticsDateRange.month,
          now: DateTime(2026, 1, 20),
        ),
      );
      expect(
        after!.averageFuelPriceMicrosPerLitre,
        before!.averageFuelPriceMicrosPerLitre,
      );
      expect(after.averageFuelEconomy.ukMpg, before.averageFuelEconomy.ukMpg);
      expect(after.fuelVolumeMillilitres, 320008);
      expect(after.fuelSpendMinor, 55656);
      expect(after.fuelPriceTrend.length, 8);
      expect(after.fuelEconomyTrend.length, 7);
      for (final record in raw) {
        final stored = await t.runAsync(() => c.refuelById(record.id));
        expect(stored!.unitPriceMicrosPerLitre, 1739170);
        expect(stored.volumeMillilitres, 40001);
      }
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
