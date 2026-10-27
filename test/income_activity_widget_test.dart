import 'package:drivetracker/features/daily_records/presentation/expense_form_screen.dart';
import 'package:drivetracker/features/daily_records/presentation/income_form_screen.dart';
import 'package:drivetracker/features/insights/presentation/insights_screen.dart';
import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/app/router/app_navigation.dart';
import 'package:drivetracker/app/theme/dt_theme.dart';
import 'package:drivetracker/features/attachments/domain/attachment_io.dart';
import 'package:drivetracker/features/daily_records/domain/daily_activity.dart';
import 'package:drivetracker/features/daily_records/domain/income.dart';
import 'package:drivetracker/features/daily_records/domain/income_activity.dart';
import 'package:drivetracker/features/daily_records/presentation/record_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/test_services.dart';
import 'income_activities_test.dart' show vehicleDraft, activityDraft, cost;

Future<void> waitFor(WidgetTester t, Finder finder) async {
  for (var i = 0; i < 200; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets);
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pump();
  await t.pump(const Duration(milliseconds: 350));
}

Future<DriveTrackerController> controllerFor(
  WidgetTester t,
  TestServices s,
) async {
  final c = DriveTrackerController(
    database: s.database,
    clock: () => DateTime(2026, 10, 21),
    attachmentStorage: ManagedAttachmentStorage(
      rootDirectory: () async => s.attachmentRoot,
    ),
    attachmentPicker: s.attachmentPicker,
    attachmentOpener: s.attachmentOpener,
  );
  await t.runAsync(c.initialize);
  return c;
}

Widget app(DriveTrackerController c, Widget home, {bool dark = false}) =>
    ChangeNotifierProvider.value(
      value: c,
      child: MaterialApp(
        theme: DTTheme.light(),
        darkTheme: DTTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: home,
      ),
    );
void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'Income Activity Details -> Edit preserves ID and fields narrow large text dark=$dark',
      (t) async {
        await t.binding.setSurfaceSize(const Size(320, 760));
        t.platformDispatcher.textScaleFactorTestValue = 1.8;
        addTearDown(() {
          t.binding.setSurfaceSize(null);
          t.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final s = createTestServices();
        late Income r;
        await t.runAsync(() async {
          final v = await s.vehicleService.addVehicle(vehicleDraft);
          r = await s.incomeService.createIncome(
            activityDraft(
              v.id,
              activity: const IncomeActivity(
                type: IncomeActivityType.delivery,
                durationMinutes: 120,
                distanceMm: 16093440,
                deliveryCount: 4,
                directCostsComplete: true,
              ),
              expenses: [cost(v.id, 500)],
            ),
          );
        });
        final c = await controllerFor(t, s);
        await t.pumpWidget(
          app(
            c,
            RecordDetailsScreen(type: DailyActivityType.income, recordId: r.id),
            dark: dark,
          ),
        );
        await waitFor(t, find.byKey(Key('recordDetailsLoaded_${r.id}')));
        await tap(t, find.byKey(const Key('recordDetailsEdit')));
        await waitFor(t, find.byKey(const Key('incomeAmountField')));
        await t.enterText(find.byKey(const Key('incomeAmountField')), '120.00');
        await waitFor(t, find.text('Direct costs are complete'));
        await tap(t, find.byKey(const Key('saveIncomeButton')));
        await waitFor(t, find.byKey(Key('recordDetailsLoaded_${r.id}')));
        await waitFor(t, find.text('£120.00'));
        final saved = await t.runAsync(() => s.incomes.getById(r.id));
        expect(saved!.id, r.id);
        expect(saved.activity.distanceMm, r.activity.distanceMm);
        expect(saved.activity.deliveryCount, 4);
        expect(
          (await t.runAsync(() => s.expenses.listForVehicle(r.vehicleId)))!,
          hasLength(1),
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
  testWidgets(
    'template changes confirm before discarding incompatible populated fields',
    (t) async {
      final s = createTestServices();
      late Income r;
      await t.runAsync(() async {
        final v = await s.vehicleService.addVehicle(vehicleDraft);
        r = await s.incomeService.createIncome(
          activityDraft(
            v.id,
            activity: const IncomeActivity(
              type: IncomeActivityType.delivery,
              deliveryCount: 4,
            ),
          ),
        );
      });
      final c = await controllerFor(t, s);
      await t.pumpWidget(app(c, IncomeFormScreen(income: r)));
      final selector = find.byWidgetPredicate(
        (w) => w is DropdownButtonFormField<IncomeActivityType>,
      );
      await waitFor(t, selector);
      await tap(t, selector);
      await t.pump(const Duration(milliseconds: 350));
      await tap(t, find.text('Rideshare').last);
      await waitFor(t, find.text('Change activity template?'));
      await tap(t, find.text('Cancel'));
      expect(
        find.byKey(const ValueKey('activityTemplate_delivery')),
        findsOneWidget,
      );
      expect(
        t
            .widget<TextFormField>(find.byKey(const Key('activity_Deliveries')))
            .controller!
            .text,
        '4',
      );
      await tap(t, selector);
      await t.pump(const Duration(milliseconds: 350));
      await tap(t, find.text('Rideshare').last);
      await tap(t, find.text('Change template'));
      expect(
        find.byKey(const ValueKey('activityTemplate_rideshare')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('activity_Deliveries')), findsNothing);
      expect(
        t
            .widget<TextFormField>(find.byKey(const Key('incomeAmountField')))
            .controller!
            .text,
        '100.00',
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'linked expense deletion explains unlinking and retains the record',
    (t) async {
      final s = createTestServices();
      late Income r;
      await t.runAsync(() async {
        final v = await s.vehicleService.addVehicle(vehicleDraft);
        r = await s.incomeService.createIncome(
          activityDraft(v.id, expenses: [cost(v.id, 500)]),
        );
      });
      final c = await controllerFor(t, s);
      final expense = (await t.runAsync(() => c.incomeExpenses(r.id)))!.single;
      await t.pumpWidget(app(c, ExpenseFormScreen(expense: expense)));
      await waitFor(t, find.byTooltip('Delete expense'));
      await tap(t, find.byTooltip('Delete expense'));
      await tap(t, find.text('Delete'));
      await waitFor(
        t,
        find.text(
          'Unlink this expense from its income activity before deleting it.',
        ),
      );
      expect(await t.runAsync(() => s.expenses.getById(expense.id)), isNotNull);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets('visited Insights earnings reload after a linked Expense edit', (
    t,
  ) async {
    final s = createTestServices();
    late Income r;
    await t.runAsync(() async {
      final v = await s.vehicleService.addVehicle(vehicleDraft);
      r = await s.incomeService.createIncome(
        activityDraft(
          v.id,
          activity: const IncomeActivity(
            type: IncomeActivityType.delivery,
            directCostsComplete: true,
          ),
          expenses: [cost(v.id, 500)],
        ),
      );
    });
    final c = await controllerFor(t, s);
    await t.pumpWidget(app(c, const InsightsScreen()));
    await waitFor(t, find.byKey(const Key('insightsScreenList')));
    final panel = find.byKey(const Key('incomeActivityEarningsPanel'));
    await t.scrollUntilVisible(
      panel,
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await waitFor(t, find.descendant(of: panel, matching: find.text('£95.00')));
    final expenses = (await t.runAsync(() => c.incomeExpenses(r.id)))!;
    await t.runAsync(
      () => c.updateExpense(expenses.single.id, cost(r.vehicleId, 1500)),
    );
    await waitFor(t, find.descendant(of: panel, matching: find.text('£85.00')));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets(
    'new delivery shift creates canonical direct expense only on save',
    (t) async {
      final s = createTestServices();
      await t.runAsync(() => s.vehicleService.addVehicle(vehicleDraft));
      final c = await controllerFor(t, s);
      await t.pumpWidget(
        app(
          c,
          Builder(
            builder: (ctx) => Scaffold(
              body: FilledButton(
                onPressed: () => AppNavigation.openIncome(ctx),
                child: const Text('Add income'),
              ),
            ),
          ),
        ),
      );
      await tap(t, find.text('Add income'));
      await waitFor(t, find.byKey(const Key('incomeAmountField')));
      await t.enterText(find.byKey(const Key('incomeAmountField')), '50');
      final selector = find.byWidgetPredicate(
        (w) => w is DropdownButtonFormField<IncomeActivityType>,
      );
      await tap(t, selector);
      await t.pumpAndSettle();
      await tap(t, find.text('Delivery shift').last);
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('activity_Deliveries')));
      await t.enterText(find.byKey(const Key('activity_Deliveries')), '5');
      await tap(t, find.text('New direct expense'));
      await waitFor(t, find.text('Add on save'));
      final amount = find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextFormField),
          )
          .first;
      await t.enterText(amount, '5');
      await tap(t, find.text('Add on save'));
      await waitFor(t, find.textContaining('New expense on save'));
      expect(
        (await t.runAsync(
          () => s.expenses.listForVehicle(c.selectedVehicle!.id),
        ))!,
        isEmpty,
      );
      await tap(t, find.byKey(const Key('saveIncomeButton')));
      await waitFor(t, find.byType(SnackBar));
      final records = (await t.runAsync(
        () => s.incomes.listForVehicle(c.selectedVehicle!.id),
      ))!;
      expect(records, hasLength(1));
      expect(records.single.activity.type, IncomeActivityType.delivery);
      expect(records.single.activity.deliveryCount, 5);
      expect(
        (await t.runAsync(() => c.incomeExpenses(records.single.id)))!,
        hasLength(1),
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
