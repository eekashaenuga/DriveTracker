import 'dart:io';
import 'dart:math';

import 'package:drivetracker/core/database/app_database.dart';
import 'package:drivetracker/core/database/database_migrations.dart';
import 'package:drivetracker/core/utilities/id_generator.dart';
import 'package:drivetracker/core/utilities/validation_exception.dart';
import 'package:drivetracker/features/attachments/data/attachment_repository.dart';
import 'package:drivetracker/features/attachments/domain/attachment.dart';
import 'package:drivetracker/features/attachments/domain/attachment_io.dart';
import 'package:drivetracker/features/attachments/domain/attachment_service.dart';
import 'package:drivetracker/features/daily_records/domain/expense.dart';
import 'package:drivetracker/features/daily_records/domain/income.dart';
import 'package:drivetracker/features/daily_records/domain/record_category.dart';
import 'package:drivetracker/features/daily_records/domain/refuel.dart';
import 'package:drivetracker/features/documents/domain/vehicle_document.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_reminder.dart';
import 'package:drivetracker/features/maintenance/domain/service_record.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_services.dart';

void main() {
  test(
    'V3 to V4 migration preserves existing data and adds document schema',
    () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('drivetracker_v3_');
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final path = p.join(dir.path, 'drive_tracker.db');
      final oldDb = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: DatabaseMigrations.createSchema,
        ),
      );
      await oldDb.insert('vehicles', _vehicleMap('veh_1'));
      await oldDb.insert('odometer_entries', _odometerMap('odo_1', 'veh_1'));
      await oldDb.insert('app_settings', {
        'key': 'selected_vehicle_id',
        'value': 'veh_1',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
      await oldDb.insert('refuels', _refuelMap('refuel_1', 'veh_1'));
      await oldDb.insert('expenses', _expenseMap('expense_1', 'veh_1'));
      await oldDb.insert('income_records', _incomeMap('income_1', 'veh_1'));
      await oldDb.insert(
        'maintenance_items',
        _maintenanceMap('maint_1', 'veh_1'),
      );
      await oldDb.insert('services', _serviceMap('service_1', 'veh_1'));
      await oldDb.insert(
        'service_items',
        _serviceItemMap('service_item_1', 'service_1', 'maint_1'),
      );
      await oldDb.close();

      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: path,
      );
      addTearDown(database.close);
      final db = await database.database;

      expect(await db.getVersion(), 4);
      expect((await db.query('vehicles')).single['id'], 'veh_1');
      expect((await db.query('odometer_entries')).single['id'], 'odo_1');
      expect((await db.query('app_settings')).single['value'], 'veh_1');
      expect((await db.query('refuels')).single['id'], 'refuel_1');
      expect((await db.query('expenses')).single['id'], 'expense_1');
      expect((await db.query('income_records')).single['id'], 'income_1');
      expect((await db.query('maintenance_items')).single['id'], 'maint_1');
      expect((await db.query('services')).single['id'], 'service_1');
      expect((await db.query('service_items')).single['id'], 'service_item_1');
      expect(await db.query('documents'), isEmpty);
      expect(await db.query('attachments'), isEmpty);
      expect(await _sqliteObjectExists(db, 'table', 'documents'), isTrue);
      expect(await _sqliteObjectExists(db, 'table', 'attachments'), isTrue);
      expect(
        await _sqliteObjectExists(
          db,
          'index',
          'idx_documents_vehicle_active_expiry',
        ),
        isTrue,
      );
      expect(
        await _sqliteObjectExists(db, 'index', 'idx_attachments_parent'),
        isTrue,
      );
    },
  );

  group('documents', () {
    test('create read update archive permanent delete and isolation', () async {
      final services = createTestServices();
      final commuter = await services.vehicleService.addVehicle(
        _draft('Commuter'),
      );
      final weekend = await services.vehicleService.addVehicle(
        _draft('Weekend'),
      );

      final document = await services.documentService.createDocument(
        VehicleDocumentDraft(
          vehicleId: commuter.id,
          category: 'Insurance',
          title: '  Policy schedule  ',
          issueDate: DateTime(2026, 9, 1),
          expiryDate: DateTime(2027, 9, 1),
          provider: '  Admiral  ',
          referenceNumber: ' ABC123 ',
          notes: ' Keep the certificate ',
        ),
      );

      expect(document.title, 'Policy schedule');
      expect(document.provider, 'Admiral');
      expect(document.referenceNumber, 'ABC123');
      expect(await services.documents.getById(document.id), isNotNull);
      expect(
        await services.documents.listForVehicle(commuter.id),
        hasLength(1),
      );
      expect(await services.documents.listForVehicle(weekend.id), isEmpty);

      final updated = await services.documentService.updateDocument(
        document.id,
        VehicleDocumentDraft(
          vehicleId: commuter.id,
          category: 'Warranty',
          title: 'Extended warranty',
          expiryDate: DateTime(2028, 1, 10),
        ),
      );
      expect(updated.category, 'Warranty');
      expect(updated.provider, isNull);
      expect(updated.updatedAt.isAfter(document.updatedAt), isTrue);

      final source = await _writeSourceFile(services, 'warranty.pdf', [
        1,
        2,
        3,
      ]);
      final attachment = await services.attachmentService.addAttachment(
        parentType: AttachmentParentType.document,
        parentId: document.id,
        source: _source(source, 'warranty.pdf'),
      );
      expect(await _managedFileExists(services, attachment), isTrue);

      await services.documentService.archiveDocument(document.id);
      expect(await services.documents.listForVehicle(commuter.id), isEmpty);
      final archived = (await services.documents.listForVehicle(
        commuter.id,
        includeArchived: true,
      )).single;
      expect(archived.isArchived, isTrue);
      expect(
        await services.attachments.listForParent(
          AttachmentParentType.document,
          document.id,
        ),
        hasLength(1),
      );

      await services.documentService.deleteDocumentPermanently(document.id);
      expect(await services.documents.getById(document.id), isNull);
      expect(
        await services.attachments.listForParent(
          AttachmentParentType.document,
          document.id,
        ),
        isEmpty,
      );
      expect(await _managedFileExists(services, attachment), isFalse);
    });

    test(
      'renew archives the old document and leaves old attachments in history',
      () async {
        final services = createTestServices();
        final vehicle = await services.vehicleService.addVehicle(
          _draft('Commuter'),
        );
        final oldDocument = await services.documentService.createDocument(
          VehicleDocumentDraft(
            vehicleId: vehicle.id,
            category: 'MOT',
            title: 'MOT certificate',
            expiryDate: DateTime(2026, 9, 20),
            provider: 'Test Centre',
          ),
        );
        final source = await _writeSourceFile(services, 'old-mot.jpg', [
          7,
          8,
          9,
        ]);
        final oldAttachment = await services.attachmentService.addAttachment(
          parentType: AttachmentParentType.document,
          parentId: oldDocument.id,
          source: _source(source, 'old-mot.jpg', mimeType: 'image/jpeg'),
        );

        final renewed = await services.documentService.renewDocument(
          oldDocument.id,
          VehicleDocumentDraft(
            vehicleId: vehicle.id,
            category: 'MOT',
            title: 'MOT certificate 2027',
            issueDate: DateTime(2026, 9, 21),
            expiryDate: DateTime(2027, 9, 20),
            provider: 'Test Centre',
          ),
        );

        final documents = await services.documents.listForVehicle(
          vehicle.id,
          includeArchived: true,
        );
        expect(
          documents.where((document) => !document.isArchived).single.id,
          renewed.id,
        );
        expect(
          documents
              .where((document) => document.id == oldDocument.id)
              .single
              .isArchived,
          isTrue,
        );
        expect(
          await services.attachments.listForParent(
            AttachmentParentType.document,
            oldDocument.id,
          ),
          hasLength(1),
        );
        expect(
          await services.attachments.listForParent(
            AttachmentParentType.document,
            renewed.id,
          ),
          isEmpty,
        );
        expect(await _managedFileExists(services, oldAttachment), isTrue);
      },
    );

    test('validation rejects missing fields and invalid date order', () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(
        _draft('Commuter'),
      );

      expect(
        () => services.documentService.createDocument(
          VehicleDocumentDraft(vehicleId: vehicle.id, category: '', title: ''),
        ),
        throwsA(
          isA<ValidationException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Category is required.'),
              contains('Title is required.'),
            ),
          ),
        ),
      );
      expect(
        () => services.documentService.createDocument(
          VehicleDocumentDraft(
            vehicleId: vehicle.id,
            category: 'Insurance',
            title: 'Policy',
            issueDate: DateTime(2027, 1, 1),
            expiryDate: DateTime(2026, 12, 31),
          ),
        ),
        throwsA(
          isA<ValidationException>().having(
            (error) => error.message,
            'message',
            contains('Expiry date cannot be before issue date.'),
          ),
        ),
      );
    });

    test(
      'status and document expiry reminders use local calendar dates',
      () async {
        final services = createTestServices();
        final vehicle = await services.vehicleService.addVehicle(
          _draft('Commuter'),
        );
        final asOf = DateTime(2026, 9, 20, 12);
        final noExpiry = _document(vehicle.id, expiryDate: null);
        final valid = _document(
          vehicle.id,
          title: 'Far future',
          expiryDate: DateTime(2026, 10, 31),
        );
        final upcoming = await services.documentService.createDocument(
          VehicleDocumentDraft(
            vehicleId: vehicle.id,
            category: 'Insurance',
            title: 'Insurance policy',
            expiryDate: DateTime(2026, 10, 10),
          ),
        );
        final dueSoon = await services.documentService.createDocument(
          VehicleDocumentDraft(
            vehicleId: vehicle.id,
            category: 'MOT',
            title: 'MOT certificate',
            expiryDate: DateTime(2026, 9, 25),
          ),
        );
        final dueToday = await services.documentService.createDocument(
          VehicleDocumentDraft(
            vehicleId: vehicle.id,
            category: 'Tax',
            title: 'Vehicle tax',
            expiryDate: DateTime(2026, 9, 20),
          ),
        );
        final expired = await services.documentService.createDocument(
          VehicleDocumentDraft(
            vehicleId: vehicle.id,
            category: 'Warranty',
            title: 'Warranty',
            expiryDate: DateTime(2026, 9, 1),
          ),
        );

        expect(noExpiry.statusAt(asOf), DocumentStatus.noExpiry);
        expect(valid.statusAt(asOf), DocumentStatus.valid);
        expect(upcoming.statusAt(asOf), DocumentStatus.expiringSoon);
        expect(expired.statusAt(asOf), DocumentStatus.expired);

        final reminders = await services.documentService.remindersForVehicle(
          vehicle.id,
          asOf: asOf,
        );
        expect(reminders.map((reminder) => reminder.document.id), [
          expired.id,
          dueToday.id,
          dueSoon.id,
          upcoming.id,
        ]);
        expect(reminders[0].state, MaintenanceReminderState.overdue);
        expect(reminders[1].state, MaintenanceReminderState.due);
        expect(reminders[2].state, MaintenanceReminderState.dueSoon);
        expect(reminders[3].state, MaintenanceReminderState.upcoming);

        await services.documentService.archiveDocument(expired.id);
        final afterArchive = await services.documentService.remindersForVehicle(
          vehicle.id,
          asOf: asOf,
        );
        expect(
          afterArchive.map((reminder) => reminder.document.id),
          isNot(contains(expired.id)),
        );
      },
    );
  });

  group('attachments', () {
    test(
      'supported files are copied with relative collision-safe paths',
      () async {
        final services = createTestServices();
        final vehicle = await services.vehicleService.addVehicle(
          _draft('Commuter'),
        );
        final document = await services.documentService.createDocument(
          VehicleDocumentDraft(
            vehicleId: vehicle.id,
            category: 'Insurance',
            title: 'Policy',
          ),
        );
        final source = await _writeSourceFile(services, 'policy.pdf', [
          1,
          2,
          3,
        ]);

        final first = await services.attachmentService.addAttachment(
          parentType: AttachmentParentType.document,
          parentId: document.id,
          source: _source(source, 'policy.pdf'),
        );
        final second = await services.attachmentService.addAttachment(
          parentType: AttachmentParentType.document,
          parentId: document.id,
          source: _source(source, 'policy.pdf'),
        );

        expect(first.fileName, 'policy.pdf');
        expect(first.mimeType, 'application/pdf');
        expect(
          first.storedPath,
          startsWith('attachments/documents/${document.id}/'),
        );
        expect(p.isAbsolute(first.storedPath), isFalse);
        expect(first.storedPath, isNot(second.storedPath));
        expect(await _managedFileExists(services, first), isTrue);
        expect(
          await services.attachments.listForParent(
            AttachmentParentType.document,
            document.id,
          ),
          hasLength(2),
        );
      },
    );

    test(
      'validation rejects unsupported empty oversized and missing files',
      () async {
        final services = createTestServices();
        final vehicle = await services.vehicleService.addVehicle(
          _draft('Commuter'),
        );
        final document = await services.documentService.createDocument(
          VehicleDocumentDraft(
            vehicleId: vehicle.id,
            category: 'Insurance',
            title: 'Policy',
          ),
        );
        final pdf = await _writeSourceFile(services, 'policy.pdf', [1]);
        final exe = await _writeSourceFile(services, 'install.exe', [1]);
        final empty = await _writeSourceFile(services, 'empty.png', const []);

        expect(
          () => services.attachmentService.addAttachment(
            parentType: AttachmentParentType.document,
            parentId: document.id,
            source: _source(exe, 'install.exe'),
          ),
          throwsA(isA<ValidationException>()),
        );
        expect(
          () => services.attachmentService.addAttachment(
            parentType: AttachmentParentType.document,
            parentId: document.id,
            source: _source(empty, 'empty.png', mimeType: 'image/png'),
          ),
          throwsA(isA<ValidationException>()),
        );
        expect(
          () => services.attachmentService.addAttachment(
            parentType: AttachmentParentType.document,
            parentId: document.id,
            source: _source(
              pdf,
              'large.pdf',
              size: AttachmentService.maxAttachmentBytes + 1,
            ),
          ),
          throwsA(isA<ValidationException>()),
        );
        expect(
          () => services.attachmentService.addAttachment(
            parentType: AttachmentParentType.document,
            parentId: document.id,
            source: const AttachmentSource(
              sourcePath: 'missing.pdf',
              fileName: 'missing.pdf',
            ),
          ),
          throwsA(isA<ValidationException>()),
        );
        expect(
          () => services.attachmentService.addAttachment(
            parentType: AttachmentParentType.document,
            parentId: 'missing',
            source: _source(pdf, 'policy.pdf'),
          ),
          throwsA(isA<ValidationException>()),
        );
      },
    );

    test('missing managed files can be removed without crashing', () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(
        _draft('Commuter'),
      );
      final document = await services.documentService.createDocument(
        VehicleDocumentDraft(
          vehicleId: vehicle.id,
          category: 'V5C',
          title: 'V5C',
        ),
      );
      final source = await _writeSourceFile(services, 'v5c.png', [1, 2, 3]);
      final attachment = await services.attachmentService.addAttachment(
        parentType: AttachmentParentType.document,
        parentId: document.id,
        source: _source(source, 'v5c.png', mimeType: 'image/png'),
      );
      await _managedFile(services, attachment).delete();

      final result = await services.attachmentService.openAttachment(
        attachment,
      );
      expect(result.status, AttachmentOpenStatus.missing);

      await services.attachmentService.removeAttachment(attachment.id);
      expect(await services.attachments.getById(attachment.id), isNull);
    });

    test(
      'document and record parent deletes clean attachment metadata and files',
      () async {
        final services = createTestServices();
        final vehicle = await services.vehicleService.addVehicle(
          _draft('Commuter'),
        );
        final expenseCategory = await _firstCategory(
          services,
          RecordCategoryType.expense,
        );
        final incomeCategory = await _firstCategory(
          services,
          RecordCategoryType.income,
        );
        final document = await services.documentService.createDocument(
          VehicleDocumentDraft(
            vehicleId: vehicle.id,
            category: 'Purchase receipt',
            title: 'Purchase receipt',
          ),
        );
        final refuel = await services.refuelService.createRefuel(
          _refuelDraft(vehicle.id),
        );
        final expense = await services.expenseService.createExpense(
          ExpenseDraft(
            vehicleId: vehicle.id,
            categoryId: expenseCategory.id,
            eventDateTime: DateTime.utc(2026, 1, 5),
            amountMinor: 1200,
          ),
        );
        final income = await services.incomeService.createIncome(
          IncomeDraft(
            vehicleId: vehicle.id,
            categoryId: incomeCategory.id,
            eventDateTime: DateTime.utc(2026, 1, 6),
            amountMinor: 4500,
          ),
        );
        final service = await services.serviceRecordService.createServiceRecord(
          ServiceRecordDraft(
            vehicleId: vehicle.id,
            eventDateTime: DateTime.utc(2026, 1, 7),
            odometer: 1200,
            totalCostMinor: 10000,
            items: const [ServiceItemDraft(itemName: 'Inspection')],
          ),
        );

        final attached = <Attachment>[
          await _attachSmallPdf(
            services,
            AttachmentParentType.document,
            document.id,
            'doc.pdf',
          ),
          await _attachSmallPdf(
            services,
            AttachmentParentType.refuel,
            refuel.id,
            'fuel.pdf',
          ),
          await _attachSmallPdf(
            services,
            AttachmentParentType.expense,
            expense.id,
            'expense.pdf',
          ),
          await _attachSmallPdf(
            services,
            AttachmentParentType.income,
            income.id,
            'income.pdf',
          ),
          await _attachSmallPdf(
            services,
            AttachmentParentType.service,
            service.record.id,
            'service.pdf',
          ),
        ];

        await services.documentService.deleteDocumentPermanently(document.id);
        await services.refuelService.deleteRefuel(refuel.id);
        await services.expenseService.deleteExpense(expense.id);
        await services.incomeService.deleteIncome(income.id);
        await services.serviceRecordService.deleteServiceRecord(
          service.record.id,
        );

        expect(
          await services.attachments.listForParent(
            AttachmentParentType.document,
            document.id,
          ),
          isEmpty,
        );
        expect(
          await services.attachments.listForParent(
            AttachmentParentType.refuel,
            refuel.id,
          ),
          isEmpty,
        );
        expect(
          await services.attachments.listForParent(
            AttachmentParentType.expense,
            expense.id,
          ),
          isEmpty,
        );
        expect(
          await services.attachments.listForParent(
            AttachmentParentType.income,
            income.id,
          ),
          isEmpty,
        );
        expect(
          await services.attachments.listForParent(
            AttachmentParentType.service,
            service.record.id,
          ),
          isEmpty,
        );
        for (final attachment in attached) {
          expect(await _managedFileExists(services, attachment), isFalse);
        }
      },
    );

    test('copied orphan file is cleaned if DB insert fails', () async {
      final services = createTestServices();
      final source = await _writeSourceFile(services, 'receipt.pdf', [1, 2, 3]);
      final storage = ManagedAttachmentStorage(
        rootDirectory: () async => services.attachmentRoot,
      );
      final service = AttachmentService(
        database: services.database,
        attachmentRepository: _FailingAttachmentRepository(services.database),
        storage: storage,
        picker: services.attachmentPicker,
        opener: services.attachmentOpener,
        parentExists: (_, _) async => true,
        idGenerator: _FixedIdGenerator('attach_fixed'),
      );

      await expectLater(
        service.addAttachment(
          parentType: AttachmentParentType.document,
          parentId: 'doc_1',
          source: _source(source, 'receipt.pdf'),
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        await File(
          p.join(
            services.attachmentRoot.path,
            'attachments',
            'documents',
            'doc_1',
            'attach_fixed.pdf',
          ),
        ).exists(),
        isFalse,
      );
    });
  });
}

VehicleDraft _draft(String name) {
  return VehicleDraft(
    name: name,
    make: 'Ford',
    model: 'Focus',
    currentOdometer: 1000,
    fuelType: FuelType.petrol,
    distanceUnit: DistanceUnit.miles,
  );
}

RefuelDraft _refuelDraft(String vehicleId) {
  return RefuelDraft(
    vehicleId: vehicleId,
    eventDateTime: DateTime.utc(2026, 1, 4),
    odometer: 1100,
    fuelType: FuelType.petrol,
    totalCostMinor: 5000,
    volumeMillilitres: 40000,
    unitPriceMicrosPerLitre: 1250000,
    isFullTank: true,
    missedPreviousRefuel: false,
  );
}

VehicleDocument _document(
  String vehicleId, {
  String title = 'Document',
  DateTime? expiryDate,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return VehicleDocument(
    id: 'doc_$title',
    vehicleId: vehicleId,
    category: 'Insurance',
    title: title,
    expiryDate: expiryDate,
    isArchived: false,
    createdAt: now,
    updatedAt: now,
  );
}

Future<RecordCategory> _firstCategory(
  TestServices services,
  RecordCategoryType type,
) async {
  return (await services.categories.listByType(type)).first;
}

Future<File> _writeSourceFile(
  TestServices services,
  String name,
  List<int> bytes,
) async {
  final file = File(p.join(services.attachmentRoot.parent.path, name));
  await file.parent.create(recursive: true);
  return file.writeAsBytes(bytes);
}

AttachmentSource _source(
  File file,
  String fileName, {
  String? mimeType,
  int? size,
}) {
  return AttachmentSource(
    sourcePath: file.path,
    fileName: fileName,
    mimeType: mimeType,
    fileSize: size,
  );
}

Future<Attachment> _attachSmallPdf(
  TestServices services,
  AttachmentParentType parentType,
  String parentId,
  String fileName,
) async {
  final file = await _writeSourceFile(services, fileName, [1, 2, 3]);
  return services.attachmentService.addAttachment(
    parentType: parentType,
    parentId: parentId,
    source: _source(file, fileName),
  );
}

File _managedFile(TestServices services, Attachment attachment) {
  return File(
    p.joinAll([
      services.attachmentRoot.path,
      ...attachment.storedPath.split('/'),
    ]),
  );
}

Future<bool> _managedFileExists(TestServices services, Attachment attachment) {
  return _managedFile(services, attachment).exists();
}

Future<bool> _sqliteObjectExists(Database db, String type, String name) async {
  final rows = await db.query(
    'sqlite_master',
    where: 'type = ? AND name = ?',
    whereArgs: [type, name],
    limit: 1,
  );
  return rows.isNotEmpty;
}

class _FixedIdGenerator extends IdGenerator {
  _FixedIdGenerator(this.id) : super(random: Random(1));

  final String id;

  @override
  String newId(String prefix) => id;
}

class _FailingAttachmentRepository extends AttachmentRepository {
  _FailingAttachmentRepository(super.database);

  @override
  Future<void> insert(
    Attachment attachment, {
    DatabaseExecutor? executor,
  }) async {
    throw StateError('Insert failed.');
  }
}

Map<String, Object?> _vehicleMap(String id) {
  return {
    'id': id,
    'name': 'Commuter',
    'make': 'Ford',
    'model': 'Focus',
    'year': null,
    'registration': null,
    'fuel_type': 'PETROL',
    'distance_unit': 'MILES',
    'photo_path': null,
    'trim': null,
    'engine': null,
    'transmission': null,
    'vin': null,
    'colour': null,
    'purchase_date': null,
    'purchase_mileage': null,
    'purchase_price': null,
    'seller': null,
    'notes': null,
    'is_archived': 0,
    'created_at': '2026-01-01T00:00:00.000Z',
    'updated_at': '2026-01-01T00:00:00.000Z',
  };
}

Map<String, Object?> _odometerMap(String id, String vehicleId) {
  return {
    'id': id,
    'vehicle_id': vehicleId,
    'odometer': 1000,
    'event_datetime': '2026-01-01T00:00:00.000Z',
    'source_type': 'MANUAL',
    'source_record_id': null,
    'created_at': '2026-01-01T00:00:00.000Z',
    'updated_at': '2026-01-01T00:00:00.000Z',
  };
}

Map<String, Object?> _refuelMap(String id, String vehicleId) {
  return {
    'id': id,
    'vehicle_id': vehicleId,
    'event_datetime': '2026-01-02T00:00:00.000Z',
    'odometer': 1100,
    'fuel_type': 'PETROL',
    'total_cost_minor': 5000,
    'volume_millilitres': 40000,
    'unit_price_micros_per_litre': 1250000,
    'is_full_tank': 1,
    'missed_previous_refuel': 0,
    'station': null,
    'notes': null,
    'created_at': '2026-01-02T00:00:00.000Z',
    'updated_at': '2026-01-02T00:00:00.000Z',
  };
}

Map<String, Object?> _expenseMap(String id, String vehicleId) {
  return {
    'id': id,
    'vehicle_id': vehicleId,
    'category_id': 'cat_expense_insurance',
    'event_datetime': '2026-01-03T00:00:00.000Z',
    'odometer': null,
    'amount_minor': 1200,
    'merchant': 'Insurer',
    'payment_method': null,
    'notes': null,
    'created_at': '2026-01-03T00:00:00.000Z',
    'updated_at': '2026-01-03T00:00:00.000Z',
  };
}

Map<String, Object?> _incomeMap(String id, String vehicleId) {
  return {
    'id': id,
    'vehicle_id': vehicleId,
    'category_id': 'cat_income_rideshare',
    'event_datetime': '2026-01-04T00:00:00.000Z',
    'odometer': null,
    'amount_minor': 4500,
    'source': 'Rideshare',
    'notes': null,
    'created_at': '2026-01-04T00:00:00.000Z',
    'updated_at': '2026-01-04T00:00:00.000Z',
  };
}

Map<String, Object?> _maintenanceMap(String id, String vehicleId) {
  return {
    'id': id,
    'vehicle_id': vehicleId,
    'name': 'Engine Oil',
    'category': null,
    'mileage_interval': 8000,
    'time_interval_days': null,
    'mileage_warning': 1000,
    'date_warning_days': 30,
    'reminder_enabled': 1,
    'is_archived': 0,
    'created_at': '2026-01-05T00:00:00.000Z',
    'updated_at': '2026-01-05T00:00:00.000Z',
  };
}

Map<String, Object?> _serviceMap(String id, String vehicleId) {
  return {
    'id': id,
    'vehicle_id': vehicleId,
    'event_datetime': '2026-01-06T00:00:00.000Z',
    'odometer': 1200,
    'total_cost_minor': 10000,
    'garage': 'ABC Garage',
    'notes': null,
    'is_baseline': 0,
    'created_at': '2026-01-06T00:00:00.000Z',
    'updated_at': '2026-01-06T00:00:00.000Z',
  };
}

Map<String, Object?> _serviceItemMap(
  String id,
  String serviceId,
  String maintenanceItemId,
) {
  return {
    'id': id,
    'service_id': serviceId,
    'maintenance_item_id': maintenanceItemId,
    'item_name': 'Engine Oil',
    'allocated_cost_minor': 9000,
    'notes': null,
    'created_at': '2026-01-06T00:00:00.000Z',
    'updated_at': '2026-01-06T00:00:00.000Z',
  };
}
