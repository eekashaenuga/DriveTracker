import 'package:drivetracker/core/utilities/validation_exception.dart';
import 'package:drivetracker/features/documents/domain/document_type.dart';
import 'package:drivetracker/features/documents/domain/vehicle_document.dart';
import 'package:drivetracker/features/documents/domain/vehicle_document_overview.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_item.dart';
import 'package:drivetracker/features/reminders/domain/date_reminder_schedule.dart';
import 'package:drivetracker/features/reminders/domain/reminder_wording.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_services.dart';

const _vehicle = VehicleDraft(
  name: 'Car',
  make: 'Ford',
  model: 'Focus',
  fuelType: FuelType.petrol,
  distanceUnit: DistanceUnit.miles,
  currentOdometer: 1000,
);
VehicleDocumentDraft _document(
  String vehicleId, {
  String category = 'MOT',
  DateTime? date,
  DateReminderSchedule? schedule,
}) => VehicleDocumentDraft(
  vehicleId: vehicleId,
  category: category,
  title: '$category record',
  expiryDate: date,
  reminderSchedule: schedule,
);

void main() {
  for (final entry in {
    ' mot ': DocumentType.mot,
    'INSURANCE': DocumentType.insurance,
    ' Tax ': DocumentType.tax,
    'Vehicle tax': DocumentType.tax,
    'v5c': DocumentType.v5c,
    'Logbook': DocumentType.v5c,
    'V5C / Logbook': DocumentType.v5c,
    'Invoice': DocumentType.receipt,
    'Receipt / Invoice': DocumentType.receipt,
    'Purchase receipt': DocumentType.receipt,
    'MOT invoice notes': DocumentType.other,
    'Tax planning': DocumentType.other,
    'Warranty': DocumentType.other,
  }.entries) {
    test(
      'exact classification: ${entry.key}',
      () => expect(DocumentType.classify(entry.key), entry.value),
    );
  }
  for (final type in [
    DocumentType.mot,
    DocumentType.insurance,
    DocumentType.tax,
  ]) {
    test('${type.label} calendar status boundaries and missing date', () {
      final now = DateTime(2026, 10, 27, 23, 59);
      expect(documentStatusLabel(type, null, now), 'Setup needed');
      expect(
        documentStatusLabel(type, DateTime(2026, 10, 26), now),
        type == DocumentType.tax ? 'Overdue' : 'Expired',
      );
      expect(
        documentStatusLabel(type, DateTime(2026, 10, 27), now),
        type == DocumentType.tax ? 'Due' : 'Expiring soon',
      );
      expect(
        documentStatusLabel(type, DateTime(2026, 11, 26), now),
        type == DocumentType.tax ? 'Due soon' : 'Expiring soon',
      );
      expect(
        documentStatusLabel(type, DateTime(2026, 11, 27), now),
        type == DocumentType.tax ? 'Due later' : 'Valid',
      );
    });
  }
  for (final type in [
    DocumentType.v5c,
    DocumentType.receipt,
    DocumentType.other,
  ]) {
    test('${type.label} informational unless expiry explicitly recorded', () {
      expect(documentStatusLabel(type, null, DateTime(2026)), 'Recorded');
      expect(
        documentStatusLabel(type, DateTime(2025), DateTime(2026)),
        'Expired',
      );
    });
  }
  test('custom text and unusual informational expiry survive edits', () async {
    final s = createTestServices();
    final v = await s.vehicleService.addVehicle(_vehicle);
    for (final category in [' My custom category ', 'V5C']) {
      final doc = await s.documentService.createDocument(
        _document(v.id, category: category, date: DateTime(2027)),
      );
      final saved = await s.documentService.updateDocument(
        doc.id,
        _document(v.id, category: category, date: DateTime(2027)),
      );
      expect(saved.category, category.trim());
      expect(saved.expiryDate, DateTime(2027));
    }
  });
  test(
    'overview is vehicle scoped and exposes every active MOT source',
    () async {
      final s = createTestServices();
      final v = await s.vehicleService.addVehicle(_vehicle);
      final other = await s.vehicleService.addVehicle(_vehicle);
      await s.documentService.createDocument(
        _document(
          v.id,
          date: DateTime(2027),
          schedule: const DateReminderSchedule(),
        ),
      );
      final archived = await s.documentService.createDocument(
        _document(
          v.id,
          date: DateTime(2028),
          schedule: const DateReminderSchedule(),
        ),
      );
      await s.documentService.archiveDocument(archived.id);
      await s.documentService.createDocument(
        _document(other.id, date: DateTime(2029)),
      );
      await s.maintenanceItemService.createMaintenanceItem(
        MaintenanceItemDraft(
          vehicleId: v.id,
          name: 'MOT',
          kind: MaintenanceRecordKind.expiry,
          expiryDate: DateTime(2028),
        ),
      );
      final overview = VehicleDocumentOverview(
        vehicleId: v.id,
        documents: [
          ...await s.documents.listForVehicle(v.id, includeArchived: true),
          ...await s.documents.listForVehicle(other.id),
        ],
        maintenance: await s.maintenanceItems.listForVehicle(v.id),
      );
      expect(overview.documents, hasLength(1));
      expect(overview.motSourceCount, 2);
      expect(overview.motNeedsReview, isTrue);
      expect(
        overview.forType(DocumentType.mot).single.expiryDate,
        DateTime(2027),
      );
      expect(overview.motItems.single.expiryDate, DateTime(2028));
    },
  );
  test('document MOT checks maintenance and supports certificate without notifications', () async {
    final s = createTestServices();
    final v = await s.vehicleService.addVehicle(_vehicle);
    final item = await s.maintenanceItemService.createMaintenanceItem(
      MaintenanceItemDraft(
        vehicleId: v.id,
        name: 'MOT',
        kind: MaintenanceRecordKind.expiry,
        expiryDate: DateTime(2027),
      ),
    );
    await expectLater(
      s.documentService.createDocument(_document(v.id, date: DateTime(2027))),
      throwsA(isA<ValidationException>()),
    );
    final certificate = await s.documentService.createDocument(
      _document(
        v.id,
        date: DateTime(2027),
        schedule: const DateReminderSchedule(),
      ),
    );
    await expectLater(
      s.documentService.updateDocument(
        certificate.id,
        _document(
          v.id,
          date: DateTime(2027),
          schedule: DateReminderSchedule.mot,
        ),
      ),
      throwsA(isA<ValidationException>()),
    );
    await s.maintenanceItemService.archiveMaintenanceItem(item.id);
    final enabled = await s.documentService.updateDocument(
      certificate.id,
      _document(v.id, date: DateTime(2027), schedule: DateReminderSchedule.mot),
    );
    expect(enabled.reminderSchedule!.dailyFromDays, 7);
  });
  test('maintenance MOT checks documents when created or re-enabled', () async {
    final s = createTestServices();
    final v = await s.vehicleService.addVehicle(_vehicle);
    final doc = await s.documentService.createDocument(
      _document(v.id, date: DateTime(2027)),
    );
    MaintenanceItemDraft draft(bool enabled) => MaintenanceItemDraft(
      vehicleId: v.id,
      name: 'MOT',
      kind: MaintenanceRecordKind.expiry,
      expiryDate: DateTime(2028),
      reminderEnabled: enabled,
    );
    await expectLater(
      s.maintenanceItemService.createMaintenanceItem(draft(true)),
      throwsA(isA<ValidationException>()),
    );
    final item = await s.maintenanceItemService.createMaintenanceItem(
      draft(false),
    );
    await expectLater(
      s.maintenanceItemService.updateMaintenanceItem(item.id, draft(true)),
      throwsA(isA<ValidationException>()),
    );
    await s.documentService.archiveDocument(doc.id);
    expect(
      (await s.maintenanceItemService.updateMaintenanceItem(
        item.id,
        draft(true),
      )).reminderEnabled,
      isTrue,
    );
  });
  test(
    'informational replacement archives original without requiring expiry',
    () async {
      final s = createTestServices();
      final v = await s.vehicleService.addVehicle(_vehicle);
      final doc = await s.documentService.createDocument(
        _document(v.id, category: 'V5C'),
      );
      final replacement = await s.documentService.renewDocument(
        doc.id,
        _document(v.id, category: 'V5C'),
      );
      expect((await s.documents.getById(doc.id))!.isArchived, isTrue);
      expect(replacement.expiryDate, isNull);
      expect(replacement.id, isNot(doc.id));
    },
  );
  test(
    'tax wording uses user-recorded due dates in notifications and validation',
    () async {
      final message = ReminderWording.message(
        vehicle: 'Car',
        name: 'Vehicle tax',
        due: DateTime(2026, 10, 27),
        asOf: DateTime(2026, 10, 27),
        expiry: false,
      );
      expect(message.title, 'Vehicle tax due today');
      expect(message.body, contains('user-recorded'));
      expect(message.body, isNot(contains('maintenance')));
      final s = createTestServices();
      final v = await s.vehicleService.addVehicle(_vehicle);
      await expectLater(
        s.documentService.createDocument(
          VehicleDocumentDraft(
            vehicleId: v.id,
            category: 'Tax',
            title: 'Tax',
            issueDate: DateTime(2028),
            expiryDate: DateTime(2027),
          ),
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            'Due date cannot be before issue date.',
          ),
        ),
      );
    },
  );
}
