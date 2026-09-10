import 'dart:io';
import 'dart:math';

import 'package:drivetracker/core/database/app_database.dart';
import 'package:drivetracker/core/utilities/id_generator.dart';
import 'package:drivetracker/features/attachments/data/attachment_repository.dart';
import 'package:drivetracker/features/attachments/domain/attachment.dart';
import 'package:drivetracker/features/attachments/domain/attachment_io.dart';
import 'package:drivetracker/features/attachments/domain/attachment_service.dart';
import 'package:drivetracker/features/daily_records/data/activity_repository.dart';
import 'package:drivetracker/features/daily_records/data/category_repository.dart';
import 'package:drivetracker/features/daily_records/data/expense_repository.dart';
import 'package:drivetracker/features/daily_records/data/financial_summary_repository.dart';
import 'package:drivetracker/features/daily_records/data/income_repository.dart';
import 'package:drivetracker/features/daily_records/data/refuel_repository.dart';
import 'package:drivetracker/features/daily_records/domain/category_service.dart';
import 'package:drivetracker/features/daily_records/domain/expense_service.dart';
import 'package:drivetracker/features/daily_records/domain/income_service.dart';
import 'package:drivetracker/features/daily_records/domain/refuel_service.dart';
import 'package:drivetracker/features/documents/data/document_repository.dart';
import 'package:drivetracker/features/documents/domain/document_service.dart';
import 'package:drivetracker/features/home/data/home_repository.dart';
import 'package:drivetracker/features/insights/data/insights_repository.dart';
import 'package:drivetracker/features/maintenance/data/maintenance_item_repository.dart';
import 'package:drivetracker/features/maintenance/data/service_record_repository.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_item_service.dart';
import 'package:drivetracker/features/maintenance/domain/service_record_service.dart';
import 'package:drivetracker/features/odometer/data/odometer_repository.dart';
import 'package:drivetracker/features/odometer/domain/odometer_service.dart';
import 'package:drivetracker/features/settings/data/settings_repository.dart';
import 'package:drivetracker/features/vehicles/data/vehicle_repository.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TestServices {
  TestServices(this.database, {Directory? attachmentRoot})
    : vehicles = VehicleRepository(database),
      odometers = OdometerRepository(database),
      settings = SettingsRepository(database),
      categories = CategoryRepository(database),
      refuels = RefuelRepository(database),
      expenses = ExpenseRepository(database),
      incomes = IncomeRepository(database),
      activities = ActivityRepository(database),
      insights = InsightsRepository(database),
      maintenanceItems = MaintenanceItemRepository(database),
      serviceRecords = ServiceRecordRepository(database),
      attachments = AttachmentRepository(database),
      documents = DocumentRepository(database),
      attachmentRoot =
          attachmentRoot ??
          Directory.systemTemp.createTempSync('drivetracker_files_'),
      attachmentPicker = TestAttachmentPicker(),
      attachmentOpener = TestAttachmentOpener() {
    final idGenerator = IdGenerator(random: Random(42));
    var clockTick = 0;
    DateTime testClock(int day, int hour) {
      final value = DateTime.utc(
        2026,
        1,
        day,
        hour,
      ).add(Duration(minutes: clockTick));
      clockTick += 1;
      return value;
    }

    vehicleService = VehicleService(
      database: database,
      vehicleRepository: vehicles,
      odometerRepository: odometers,
      settingsRepository: settings,
      idGenerator: idGenerator,
      clock: () => testClock(1, 12),
    );
    odometerService = OdometerService(
      vehicleRepository: vehicles,
      odometerRepository: odometers,
      idGenerator: idGenerator,
      clock: () => testClock(2, 12),
    );
    categoryService = CategoryService(
      categoryRepository: categories,
      idGenerator: idGenerator,
      clock: () => testClock(2, 13),
    );
    attachmentService = AttachmentService(
      database: database,
      attachmentRepository: attachments,
      storage: ManagedAttachmentStorage(
        rootDirectory: () async => this.attachmentRoot,
      ),
      picker: attachmentPicker,
      opener: attachmentOpener,
      parentExists: _parentExists,
      idGenerator: idGenerator,
      clock: () => testClock(2, 14),
    );
    documentService = DocumentService(
      database: database,
      vehicleRepository: vehicles,
      documentRepository: documents,
      attachmentRepository: attachments,
      attachmentService: attachmentService,
      idGenerator: idGenerator,
      clock: () => testClock(2, 15),
    );
    refuelService = RefuelService(
      database: database,
      vehicleRepository: vehicles,
      odometerRepository: odometers,
      refuelRepository: refuels,
      attachmentService: attachmentService,
      idGenerator: idGenerator,
      clock: () => testClock(3, 12),
    );
    expenseService = ExpenseService(
      database: database,
      vehicleRepository: vehicles,
      categoryRepository: categories,
      odometerRepository: odometers,
      expenseRepository: expenses,
      attachmentService: attachmentService,
      idGenerator: idGenerator,
      clock: () => testClock(4, 12),
    );
    incomeService = IncomeService(
      database: database,
      vehicleRepository: vehicles,
      categoryRepository: categories,
      odometerRepository: odometers,
      incomeRepository: incomes,
      attachmentService: attachmentService,
      idGenerator: idGenerator,
      clock: () => testClock(5, 12),
    );
    financialSummary = FinancialSummaryRepository(
      refuelRepository: refuels,
      expenseRepository: expenses,
      serviceRecordRepository: serviceRecords,
    );
    homeRepository = HomeRepository(
      vehicleRepository: vehicles,
      odometerRepository: odometers,
      refuelRepository: refuels,
      financialSummaryRepository: financialSummary,
      activityRepository: activities,
      maintenanceItemRepository: maintenanceItems,
      serviceRecordRepository: serviceRecords,
    );
    maintenanceItemService = MaintenanceItemService(
      vehicleRepository: vehicles,
      maintenanceItemRepository: maintenanceItems,
      serviceRecordRepository: serviceRecords,
      idGenerator: idGenerator,
      clock: () => testClock(6, 12),
    );
    serviceRecordService = ServiceRecordService(
      database: database,
      vehicleRepository: vehicles,
      maintenanceItemRepository: maintenanceItems,
      odometerRepository: odometers,
      serviceRecordRepository: serviceRecords,
      attachmentService: attachmentService,
      idGenerator: idGenerator,
      clock: () => testClock(7, 12),
    );
  }

  final AppDatabase database;
  final VehicleRepository vehicles;
  final OdometerRepository odometers;
  final SettingsRepository settings;
  final CategoryRepository categories;
  final RefuelRepository refuels;
  final ExpenseRepository expenses;
  final IncomeRepository incomes;
  final ActivityRepository activities;
  final InsightsRepository insights;
  final MaintenanceItemRepository maintenanceItems;
  final ServiceRecordRepository serviceRecords;
  final AttachmentRepository attachments;
  final DocumentRepository documents;
  final Directory attachmentRoot;
  final TestAttachmentPicker attachmentPicker;
  final TestAttachmentOpener attachmentOpener;
  late final VehicleService vehicleService;
  late final OdometerService odometerService;
  late final CategoryService categoryService;
  late final RefuelService refuelService;
  late final ExpenseService expenseService;
  late final IncomeService incomeService;
  late final FinancialSummaryRepository financialSummary;
  late final HomeRepository homeRepository;
  late final MaintenanceItemService maintenanceItemService;
  late final ServiceRecordService serviceRecordService;
  late final AttachmentService attachmentService;
  late final DocumentService documentService;

  Future<bool> _parentExists(
    AttachmentParentType parentType,
    String parentId,
  ) async {
    return switch (parentType) {
      AttachmentParentType.document =>
        await documents.getById(parentId) != null,
      AttachmentParentType.refuel => await refuels.getById(parentId) != null,
      AttachmentParentType.service =>
        await serviceRecords.getById(parentId) != null,
      AttachmentParentType.expense => await expenses.getById(parentId) != null,
      AttachmentParentType.income => await incomes.getById(parentId) != null,
      AttachmentParentType.vehicle => await vehicles.getById(parentId) != null,
    };
  }
}

class TestAttachmentPicker implements AttachmentPicker {
  AttachmentSource? nextSource;
  int pickCount = 0;

  @override
  Future<AttachmentSource?> pickAttachment() async {
    pickCount += 1;
    final source = nextSource;
    nextSource = null;
    return source;
  }
}

class TestAttachmentOpener implements AttachmentOpener {
  AttachmentOpenResult nextResult = const AttachmentOpenResult(
    AttachmentOpenStatus.opened,
  );
  final opened = <String>[];

  @override
  Future<AttachmentOpenResult> openAttachment({
    required String absolutePath,
    required String? mimeType,
  }) async {
    opened.add(absolutePath);
    return nextResult;
  }
}

TestServices createTestServices() {
  sqfliteFfiInit();
  final dir = Directory.systemTemp.createTempSync('drivetracker_test_');
  final database = AppDatabase(
    databaseFactory: databaseFactoryFfi,
    databasePath: p.join(dir.path, 'drive_tracker.db'),
  );
  addTearDown(() async {
    await database.close();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  return TestServices(
    database,
    attachmentRoot: Directory(p.join(dir.path, 'files')),
  );
}

Future<TestServices> createFileBackedTestServices() async {
  sqfliteFfiInit();
  final dir = await Directory.systemTemp.createTemp('drivetracker_test_');

  final database = AppDatabase(
    databaseFactory: databaseFactoryFfi,
    databasePath: p.join(dir.path, 'drive_tracker.db'),
  );
  addTearDown(() async {
    await database.close();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  return TestServices(
    database,
    attachmentRoot: Directory(p.join(dir.path, 'files')),
  );
}
