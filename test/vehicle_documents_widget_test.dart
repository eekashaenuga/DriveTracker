import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/app/theme/dt_theme.dart';
import 'package:drivetracker/features/documents/domain/vehicle_document.dart';
import 'package:drivetracker/features/documents/presentation/document_form_screen.dart';
import 'package:drivetracker/features/documents/presentation/documents_screen.dart';
import 'package:drivetracker/features/documents/presentation/vehicle_documents_overview.dart';
import 'package:drivetracker/features/reminders/domain/date_reminder_schedule.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_item.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/test_services.dart';

const _draft = VehicleDraft(
  name: 'Car',
  make: 'Ford',
  model: 'Focus',
  fuelType: FuelType.petrol,
  distanceUnit: DistanceUnit.miles,
  currentOdometer: 1000,
);
Future<void> _wait(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 70 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
}

DriveTrackerController _controller(TestServices services) =>
    DriveTrackerController(
      database: services.database,
      clock: () => DateTime(2026, 10, 27),
    );
Widget _app(
  DriveTrackerController controller,
  Widget child, {
  bool dark = false,
}) => ChangeNotifierProvider.value(
  value: controller,
  child: MaterialApp(
    theme: dark ? DTTheme.dark() : DTTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(2), disableAnimations: true),
      child: child!,
    ),
    home: child,
  ),
);

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'overview shows conflicting MOT sources at large text dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final s = createTestServices();
        final v = (await tester.runAsync(
          () => s.vehicleService.addVehicle(_draft),
        ))!;
        final doc = (await tester.runAsync(
          () => s.documentService.createDocument(
            VehicleDocumentDraft(
              vehicleId: v.id,
              category: 'MOT',
              title: 'Certificate',
              expiryDate: DateTime(2027),
              reminderSchedule: const DateReminderSchedule(),
            ),
          ),
        ))!;
        final item = (await tester.runAsync(
          () => s.maintenanceItemService.createMaintenanceItem(
            MaintenanceItemDraft(
              vehicleId: v.id,
              name: 'MOT',
              kind: MaintenanceRecordKind.expiry,
              expiryDate: DateTime(2028),
            ),
          ),
        ))!;
        final controller = _controller(s);
        addTearDown(controller.dispose);
        await tester.runAsync(controller.initialize);
        await tester.pumpWidget(
          _app(
            controller,
            Scaffold(
              body: SingleChildScrollView(
                child: VehicleDocumentsOverview(vehicleId: v.id),
              ),
            ),
            dark: dark,
          ),
        );
        await _wait(
          tester,
          find.text('Review needed: multiple active MOT sources'),
        );
        expect(find.byKey(Key('complianceDocument_${doc.id}')), findsOneWidget);
        expect(
          find.byKey(Key('complianceMaintenance_${item.id}')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(Key('complianceMaintenance_${item.id}')),
        );
        await tester.tap(find.byKey(Key('complianceMaintenance_${item.id}')));
        await tester.pumpAndSettle();
        expect(find.text('Edit expiry reminder'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'scoped Documents loads requested vehicle without changing selection',
    (tester) async {
      final s = createTestServices();
      final a = (await tester.runAsync(
        () => s.vehicleService.addVehicle(_draft),
      ))!;
      final b = (await tester.runAsync(
        () => s.vehicleService.addVehicle(_draft),
      ))!;
      await tester.runAsync(
        () => s.documentService.createDocument(
          VehicleDocumentDraft(
            vehicleId: a.id,
            category: 'V5C',
            title: 'A logbook',
          ),
        ),
      );
      await tester.runAsync(
        () => s.documentService.createDocument(
          VehicleDocumentDraft(
            vehicleId: b.id,
            category: 'V5C',
            title: 'B logbook',
          ),
        ),
      );
      final controller = _controller(s);
      addTearDown(controller.dispose);
      await tester.runAsync(controller.initialize);
      await tester.runAsync(() => controller.selectVehicle(a.id));
      await tester.pumpWidget(
        _app(controller, DocumentsScreen(vehicleId: b.id)),
      );
      await _wait(tester, find.textContaining('B logbook'));
      await _wait(tester, find.text('0 other documents / 0 document files'));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
      expect(find.textContaining('A logbook'), findsNothing);
      expect(controller.selectedVehicle!.id, a.id);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'tax and informational forms reveal only configured expiry workflow',
    (tester) async {
      final s = createTestServices();
      final v = (await tester.runAsync(
        () => s.vehicleService.addVehicle(_draft),
      ))!;
      final controller = _controller(s);
      addTearDown(controller.dispose);
      await tester.runAsync(controller.initialize);
      await tester.pumpWidget(
        _app(
          controller,
          DocumentFormScreen(vehicleId: v.id, initialCategory: 'Vehicle tax'),
        ),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('documentExpiryDateField')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Due date'), findsWidgets);
      expect(find.text('Expiry date'), findsNothing);
      await tester.pumpWidget(
        _app(
          controller,
          DocumentFormScreen(
            key: const ValueKey('v5c'),
            vehicleId: v.id,
            initialCategory: 'V5C',
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Record an expiry date'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('documentExpiryDateField')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
