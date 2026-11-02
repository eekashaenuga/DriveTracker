import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:drivetracker/core/calculations/analytics_date_range.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/app/theme/dt_theme.dart';
import 'package:drivetracker/features/reports/data/report_repository.dart';
import 'package:drivetracker/features/reports/domain/report_request.dart';
import 'package:drivetracker/features/reports/domain/report_service.dart';
import 'package:drivetracker/features/reports/presentation/export_reports_screen.dart';

import 'helpers/report_fixture.dart';
import 'helpers/report_file_bridge.dart';

class UiReportService extends ReportService {
  UiReportService(super.repository, TestReportBridge bridge)
    : super(bridge: bridge);
  int calls = 0;
  bool fail = false;
  Completer<ReportArtifact>? pending;
  ReportRequest? request;
  @override
  Future<ReportArtifact> generate(ReportRequest value) async {
    calls++;
    request = value;
    if (fail) throw const ReportException('Controlled generation failure');
    return pending?.future ??
        ReportArtifact(
          path: 'cached/report.${value.format.name}',
          name: 'Vehnora_report.${value.format.name}',
          format: value.format,
          size: 2048,
          recordCount: 1,
        );
  }
}

Future<void> settleDb(WidgetTester t, bool Function() predicate) async {
  for (var i = 0; i < 300 && !predicate(); i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 20));
  }
  expect(predicate(), isTrue);
}

Future<void> show(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(
    f,
    250,
    scrollable: find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first,
  );
  await t.ensureVisible(f);
  await t.pump(const Duration(milliseconds: 100));
}

Future<(UiReportService, TestReportBridge)> setupReports(
  WidgetTester t, {
  bool dark = false,
  double scale = 1,
}) async {
  late UiReportService service;
  late DriveTrackerController c;
  final bridge = TestReportBridge(Directory.systemTemp);
  await t.runAsync(() async {
    final (s, _) = await reportFixture();
    c = DriveTrackerController(database: s.database);
    await c.initialize();
    service = UiReportService(
      ReportRepository(s.database, clock: () => reportNow),
      bridge,
    );
  });
  addTearDown(c.dispose);
  await t.pumpWidget(
    ChangeNotifierProvider<DriveTrackerController>.value(
      value: c,
      child: MaterialApp(
        theme: DTTheme.light(),
        darkTheme: DTTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: ExportReportsScreen(service: service),
      ),
    ),
  );
  return (service, bridge);
}

void main() {
  testWidgets(
    'archived vehicle selection is deliberate and does not change Home selection',
    (t) async {
      final (service, _) = await setupReports(t);
      final c = t
          .element(find.byType(ExportReportsScreen))
          .read<DriveTrackerController>();
      final original = c.selectedVehicle!.id;
      final archived = await t.runAsync(
        () => c.addVehicle(
          const VehicleDraft(
            name: 'Archived car',
            make: 'Kia',
            model: 'Rio',
            fuelType: FuelType.diesel,
            distanceUnit: DistanceUnit.kilometers,
            currentOdometer: 1000,
          ),
        ),
      );
      await t.runAsync(() => c.archiveVehicle(archived!.id));
      await t.pump();
      await t.tap(
        find.widgetWithText(SwitchListTile, 'Show archived vehicles'),
      );
      await t.pump();
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Archived car (archived)').last);
      await t.pumpAndSettle();
      await show(t, find.byKey(const Key('reportGenerate')));
      await t.tap(find.byKey(const Key('reportGenerate')));
      await t.pump();
      await settleDb(t, () => service.request != null);
      expect(service.request!.vehicleId, archived!.id);
      expect(c.selectedVehicle!.id, original);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'custom range picker can be opened and cancelled without changing selection',
    (t) async {
      final (service, _) = await setupReports(t);
      await t.tap(find.byType(DropdownButtonFormField<AnalyticsRangePreset>));
      await t.pumpAndSettle();
      await t.tap(find.text('Custom').last);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('reportCustomRange')), findsOneWidget);
      await t.tap(find.byTooltip('Close'));
      await t.pumpAndSettle();
      expect(
        t
            .state<FormFieldState<AnalyticsRangePreset>>(
              find.byType(DropdownButtonFormField<AnalyticsRangePreset>),
            )
            .value,
        AnalyticsRangePreset.month,
      );
      await show(t, find.byKey(const Key('reportGenerate')));
      await t.tap(find.byKey(const Key('reportGenerate')));
      await t.pump();
      await settleDb(t, () => service.request != null);
      expect(service.request!.range.preset, AnalyticsRangePreset.month);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'default document privacy output selection and successful Open Share Save cancellation',
    (t) async {
      final (service, bridge) = await setupReports(t);
      final docs = find.byKey(const Key('reportSection_documents'));
      await show(t, docs);
      expect(t.widget<CheckboxListTile>(docs).value, isFalse);
      await t.tap(docs);
      await t.pump();
      await show(t, find.text('PDF report'));
      await t.tap(find.text('PDF report'));
      await t.pump();
      await show(t, find.byKey(const Key('reportGenerate')));
      await t.tap(find.byKey(const Key('reportGenerate')));
      await t.pump();
      await settleDb(
        t,
        () => find.text('Generated report').evaluate().isNotEmpty,
      );
      expect(service.request!.format, ReportFormat.pdf);
      expect(service.request!.sections, contains(ReportSection.documents));
      expect(service.request!.includeSensitive, isFalse);
      for (final action in ['Open', 'Share', 'Save']) {
        bridge.cancel = action == 'Save';
        await show(t, find.text(action));
        await t.tap(find.text(action));
        await t.pump();
      }
      expect(bridge.calls, ['Open', 'Share', 'Save']);
      expect(find.textContaining('Save cancelled'), findsOneWidget);
      expect(find.text('Generated report'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'busy prevents duplicate generation; configuration and result use captured request',
    (t) async {
      final (service, _) = await setupReports(t);
      service.pending = Completer<ReportArtifact>();
      await show(t, find.byKey(const Key('reportGenerate')));
      await t.tap(find.byKey(const Key('reportGenerate')));
      await t.pump();
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('reportGenerate')))
            .onPressed,
        isNull,
      );
      expect(service.calls, 1);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      service.pending!.complete(
        const ReportArtifact(
          path: 'cache/a.xlsx',
          name: 'a.xlsx',
          format: ReportFormat.xlsx,
          size: 100,
          recordCount: 0,
        ),
      );
      await t.pump();
      await settleDb(
        t,
        () => find.text('Generated report').evaluate().isNotEmpty,
      );
      await show(t, find.textContaining('No selected transaction records'));
      expect(
        find.textContaining('No selected transaction records'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'generation failure Retry and action failure keep artifact usable',
    (t) async {
      final (service, bridge) = await setupReports(t);
      service.fail = true;
      await show(t, find.byKey(const Key('reportGenerate')));
      await t.tap(find.byKey(const Key('reportGenerate')));
      await t.pump();
      expect(find.text('Controlled generation failure'), findsOneWidget);
      service.fail = false;
      await show(t, find.text('Retry'));
      await t.tap(find.text('Retry'));
      await t.pump();
      await settleDb(
        t,
        () => find.text('Generated report').evaluate().isNotEmpty,
      );
      bridge.fail = true;
      await show(t, find.text('Share'));
      await t.tap(find.text('Share'));
      await t.pump();
      expect(find.textContaining('Share failed'), findsOneWidget);
      bridge.fail = false;
      await show(t, find.text('Retry'));
      await t.tap(find.text('Retry'));
      await t.pump();
      expect(bridge.calls, ['Share', 'Share']);
      expect(find.text('Generated report'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final dark in [false, true]) {
    testWidgets('narrow large text themes and reduced motion dark=$dark', (
      t,
    ) async {
      t.view.physicalSize = const Size(320, 850);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final (service, _) = await setupReports(t, dark: dark, scale: 1.8);
      final handle = t.ensureSemantics();
      await show(t, find.byKey(const Key('reportGenerate')));
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const Key('reportGenerate')));
      await t.pump();
      await settleDb(
        t,
        () => find.text('Generated report').evaluate().isNotEmpty,
      );
      await show(t, find.text('Save'));
      expect(t.takeException(), isNull);
      expect(service.calls, 1);
      await t.pumpWidget(const SizedBox.shrink());
      handle.dispose();
    });
  }
  testWidgets('date and section selection remain transient', (t) async {
    final (service, _) = await setupReports(t);
    await t.tap(find.byType(DropdownButtonFormField<AnalyticsRangePreset>));
    await t.pumpAndSettle();
    await t.tap(find.text('All time').last);
    await t.pumpAndSettle();
    final fuel = find.byKey(const Key('reportSection_fuel'));
    await show(t, fuel);
    await t.tap(fuel);
    await t.pump();
    await show(t, find.byKey(const Key('reportGenerate')));
    await t.tap(find.byKey(const Key('reportGenerate')));
    await t.pump();
    await settleDb(t, () => service.request != null);
    expect(service.request!.sections, isNot(contains(ReportSection.fuel)));
    await t.pumpWidget(const SizedBox.shrink());
  });
}
