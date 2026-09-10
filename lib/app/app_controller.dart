import 'package:flutter/material.dart';

import '../core/calculations/analytics_date_range.dart';
import '../core/database/app_database.dart';
import '../core/utilities/validation_exception.dart';
import '../features/attachments/data/attachment_repository.dart';
import '../features/attachments/domain/attachment.dart';
import '../features/attachments/domain/attachment_io.dart';
import '../features/attachments/domain/attachment_service.dart';
import '../features/calculator/domain/fuel_calculator.dart';
import '../features/daily_records/data/activity_repository.dart';
import '../features/daily_records/data/category_repository.dart';
import '../features/daily_records/data/expense_repository.dart';
import '../features/daily_records/data/financial_summary_repository.dart';
import '../features/daily_records/data/income_repository.dart';
import '../features/daily_records/data/refuel_repository.dart';
import '../features/daily_records/domain/category_service.dart';
import '../features/daily_records/domain/daily_activity.dart';
import '../features/daily_records/domain/expense.dart';
import '../features/daily_records/domain/expense_service.dart';
import '../features/daily_records/domain/fuel_economy_calculator.dart';
import '../features/daily_records/domain/history_filter.dart';
import '../features/daily_records/domain/income.dart';
import '../features/daily_records/domain/income_service.dart';
import '../features/daily_records/domain/monthly_spending.dart';
import '../features/daily_records/domain/record_category.dart';
import '../features/daily_records/domain/refuel.dart';
import '../features/daily_records/domain/refuel_service.dart';
import '../features/documents/data/document_repository.dart';
import '../features/documents/domain/document_service.dart';
import '../features/documents/domain/vehicle_document.dart';
import '../features/home/data/home_repository.dart';
import '../features/home/domain/vehicle_dashboard.dart';
import '../features/insights/data/insights_repository.dart';
import '../features/insights/domain/vehicle_insights.dart';
import '../features/maintenance/data/maintenance_item_repository.dart';
import '../features/maintenance/data/service_record_repository.dart';
import '../features/maintenance/domain/maintenance_item.dart';
import '../features/maintenance/domain/maintenance_item_service.dart';
import '../features/maintenance/domain/maintenance_reminder.dart';
import '../features/maintenance/domain/service_record.dart';
import '../features/maintenance/domain/service_record_service.dart';
import '../features/odometer/data/odometer_repository.dart';
import '../features/odometer/domain/odometer_entry.dart';
import '../features/odometer/domain/odometer_policy.dart';
import '../features/odometer/domain/odometer_service.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/vehicles/data/vehicle_repository.dart';
import '../features/vehicles/domain/vehicle.dart';
import '../features/vehicles/domain/vehicle_draft.dart';
import '../features/vehicles/domain/vehicle_service.dart';

class DriveTrackerController extends ChangeNotifier {
  DriveTrackerController({
    required AppDatabase database,
    DateTime Function()? clock,
    AttachmentStorage? attachmentStorage,
    AttachmentPicker? attachmentPicker,
    AttachmentOpener? attachmentOpener,
  }) : _database = database,
       _clock = clock ?? DateTime.now,
       _vehicleRepository = VehicleRepository(database),
       _odometerRepository = OdometerRepository(database),
       _settingsRepository = SettingsRepository(database),
       _categoryRepository = CategoryRepository(database),
       _refuelRepository = RefuelRepository(database),
       _expenseRepository = ExpenseRepository(database),
       _incomeRepository = IncomeRepository(database),
       _activityRepository = ActivityRepository(database),
       _insightsRepository = InsightsRepository(database),
       _maintenanceItemRepository = MaintenanceItemRepository(database),
       _serviceRecordRepository = ServiceRecordRepository(database),
       _attachmentRepository = AttachmentRepository(database),
       _documentRepository = DocumentRepository(database) {
    final financialSummaryRepository = FinancialSummaryRepository(
      refuelRepository: _refuelRepository,
      expenseRepository: _expenseRepository,
      serviceRecordRepository: _serviceRecordRepository,
    );
    _homeRepository = HomeRepository(
      vehicleRepository: _vehicleRepository,
      odometerRepository: _odometerRepository,
      refuelRepository: _refuelRepository,
      financialSummaryRepository: financialSummaryRepository,
      activityRepository: _activityRepository,
      maintenanceItemRepository: _maintenanceItemRepository,
      serviceRecordRepository: _serviceRecordRepository,
    );
    _vehicleService = VehicleService(
      database: _database,
      vehicleRepository: _vehicleRepository,
      odometerRepository: _odometerRepository,
      settingsRepository: _settingsRepository,
    );
    _odometerService = OdometerService(
      vehicleRepository: _vehicleRepository,
      odometerRepository: _odometerRepository,
    );
    _categoryService = CategoryService(categoryRepository: _categoryRepository);
    _attachmentService = AttachmentService(
      database: _database,
      attachmentRepository: _attachmentRepository,
      storage: attachmentStorage ?? ManagedAttachmentStorage(),
      picker: attachmentPicker ?? const PlatformAttachmentPicker(),
      opener: attachmentOpener ?? const PlatformAttachmentOpener(),
      parentExists: _attachmentParentExists,
    );
    _documentService = DocumentService(
      database: _database,
      vehicleRepository: _vehicleRepository,
      documentRepository: _documentRepository,
      attachmentRepository: _attachmentRepository,
      attachmentService: _attachmentService,
      clock: () => _clock().toUtc(),
    );
    _refuelService = RefuelService(
      database: _database,
      vehicleRepository: _vehicleRepository,
      odometerRepository: _odometerRepository,
      refuelRepository: _refuelRepository,
      attachmentService: _attachmentService,
    );
    _expenseService = ExpenseService(
      database: _database,
      vehicleRepository: _vehicleRepository,
      categoryRepository: _categoryRepository,
      odometerRepository: _odometerRepository,
      expenseRepository: _expenseRepository,
      attachmentService: _attachmentService,
    );
    _incomeService = IncomeService(
      database: _database,
      vehicleRepository: _vehicleRepository,
      categoryRepository: _categoryRepository,
      odometerRepository: _odometerRepository,
      incomeRepository: _incomeRepository,
      attachmentService: _attachmentService,
    );
    _maintenanceItemService = MaintenanceItemService(
      vehicleRepository: _vehicleRepository,
      maintenanceItemRepository: _maintenanceItemRepository,
      serviceRecordRepository: _serviceRecordRepository,
    );
    _serviceRecordService = ServiceRecordService(
      database: _database,
      vehicleRepository: _vehicleRepository,
      maintenanceItemRepository: _maintenanceItemRepository,
      odometerRepository: _odometerRepository,
      serviceRecordRepository: _serviceRecordRepository,
      attachmentService: _attachmentService,
    );
  }

  static const _themeSystem = 'system';
  static const _themeLight = 'light';
  static const _themeDark = 'dark';

  final AppDatabase _database;
  final DateTime Function() _clock;
  final VehicleRepository _vehicleRepository;
  final OdometerRepository _odometerRepository;
  final SettingsRepository _settingsRepository;
  final CategoryRepository _categoryRepository;
  final RefuelRepository _refuelRepository;
  final ExpenseRepository _expenseRepository;
  final IncomeRepository _incomeRepository;
  final ActivityRepository _activityRepository;
  final InsightsRepository _insightsRepository;
  final MaintenanceItemRepository _maintenanceItemRepository;
  final ServiceRecordRepository _serviceRecordRepository;
  final AttachmentRepository _attachmentRepository;
  final DocumentRepository _documentRepository;
  late final HomeRepository _homeRepository;
  late final VehicleService _vehicleService;
  late final OdometerService _odometerService;
  late final CategoryService _categoryService;
  late final AttachmentService _attachmentService;
  late final DocumentService _documentService;
  late final RefuelService _refuelService;
  late final ExpenseService _expenseService;
  late final IncomeService _incomeService;
  late final MaintenanceItemService _maintenanceItemService;
  late final ServiceRecordService _serviceRecordService;

  bool _initialized = false;
  bool _busy = false;
  String? _errorMessage;
  ThemeMode _themeMode = ThemeMode.system;
  List<Vehicle> _activeVehicles = const [];
  List<Vehicle> _archivedVehicles = const [];
  VehicleDashboard? _dashboard;

  bool get initialized => _initialized;
  bool get isBusy => _busy;
  String? get errorMessage => _errorMessage;
  ThemeMode get themeMode => _themeMode;
  DateTime get currentTime => _clock();
  List<Vehicle> get activeVehicles => List.unmodifiable(_activeVehicles);
  List<Vehicle> get archivedVehicles => List.unmodifiable(_archivedVehicles);
  bool get hasAnyVehicles =>
      _activeVehicles.isNotEmpty || _archivedVehicles.isNotEmpty;
  bool get hasActiveVehicles => _activeVehicles.isNotEmpty;
  Vehicle? get selectedVehicle => _dashboard?.vehicle;
  int? get currentOdometer => _dashboard?.currentOdometer;
  List<OdometerEntry> get recentOdometerEntries {
    return List.unmodifiable(_dashboard?.recentOdometerEntries ?? const []);
  }

  int get monthSpendMinor => _dashboard?.monthSpendMinor ?? 0;
  int? get latestFuelPriceMicrosPerLitre {
    return _dashboard?.latestFuelPriceMicrosPerLitre;
  }

  FuelEconomyInterval? get latestFuelEconomyInterval {
    return _dashboard?.latestFuelEconomyInterval;
  }

  VehicleFuelDefaults get vehicleFuelDefaults {
    return VehicleFuelDefaults.fromDashboard(
      vehicle: selectedVehicle,
      latestFuelEconomyInterval: latestFuelEconomyInterval,
      latestFuelPriceMicrosPerLitre: latestFuelPriceMicrosPerLitre,
    );
  }

  List<DailyActivity> get recentActivity {
    return List.unmodifiable(_dashboard?.recentActivity ?? const []);
  }

  MaintenanceReminder? get nextMaintenanceAttention {
    return _dashboard?.nextMaintenanceAttention;
  }

  List<MonthlySpending> get spendingTrend {
    return List.unmodifiable(_dashboard?.spendingTrend ?? const []);
  }

  Future<int?> currentOdometerForVehicle(String vehicleId) {
    return _odometerRepository.currentOdometerForVehicle(vehicleId);
  }

  Future<List<OdometerEntry>> odometerEntriesForVehicle(String vehicleId) {
    return _odometerRepository.recentForVehicle(vehicleId, limit: 20);
  }

  Future<List<RecordCategory>> categoriesFor(RecordCategoryType type) {
    return _categoryRepository.listByType(type);
  }

  Future<List<DailyActivity>> historyForSelectedVehicle({
    DailyActivityType type = DailyActivityType.all,
  }) {
    final vehicle = selectedVehicle;
    if (vehicle == null) {
      return Future.value(const []);
    }
    return _activityRepository.listForVehicle(
      vehicle.id,
      type: type,
      limit: 100,
    );
  }

  Future<List<DailyActivity>> history(HistoryFilter filter) {
    return _activityRepository.search(filter, now: _clock());
  }

  Future<VehicleInsights> insightsFor({
    required String? vehicleId,
    required AnalyticsDateRange range,
  }) {
    return _insightsRepository.loadInsights(
      vehicleId: vehicleId,
      range: range,
      now: _clock(),
    );
  }

  Future<Refuel?> refuelById(String id) => _refuelRepository.getById(id);
  Future<Expense?> expenseById(String id) => _expenseRepository.getById(id);
  Future<Income?> incomeById(String id) => _incomeRepository.getById(id);
  Future<MaintenanceItem?> maintenanceItemById(String id) {
    return _maintenanceItemRepository.getById(id);
  }

  Future<ServiceRecordWithItems?> serviceRecordById(String id) {
    return _serviceRecordRepository.getWithItems(id);
  }

  Future<VehicleDocument?> documentById(String id) {
    return _documentRepository.getById(id);
  }

  Future<List<VehicleDocument>> documentsForSelectedVehicle({
    bool includeArchived = false,
  }) {
    final vehicle = selectedVehicle;
    if (vehicle == null) {
      return Future.value(const []);
    }
    return _documentRepository.listForVehicle(
      vehicle.id,
      includeArchived: includeArchived,
    );
  }

  Future<List<VehicleDocument>> documentsForVehicle(
    String vehicleId, {
    bool includeArchived = false,
  }) {
    return _documentRepository.listForVehicle(
      vehicleId,
      includeArchived: includeArchived,
    );
  }

  Future<List<Attachment>> attachmentsForParent(
    AttachmentParentType parentType,
    String parentId,
  ) {
    return _attachmentService.listForParent(parentType, parentId);
  }

  Future<List<MaintenanceItem>> maintenanceItemsForSelectedVehicle({
    bool includeArchived = false,
  }) {
    final vehicle = selectedVehicle;
    if (vehicle == null) {
      return Future.value(const []);
    }
    return _maintenanceItemRepository.listForVehicle(
      vehicle.id,
      includeArchived: includeArchived,
    );
  }

  Future<List<MaintenanceItem>> maintenanceItemsForVehicle(
    String vehicleId, {
    bool includeArchived = false,
  }) {
    return _maintenanceItemRepository.listForVehicle(
      vehicleId,
      includeArchived: includeArchived,
    );
  }

  Future<List<MaintenanceReminder>> maintenanceRemindersForSelectedVehicle() {
    final vehicle = selectedVehicle;
    if (vehicle == null) {
      return Future.value(const []);
    }
    return _maintenanceItemService.remindersForVehicle(
      vehicle.id,
      currentOdometer: currentOdometer,
    );
  }

  Future<List<DocumentExpiryReminder>> documentRemindersForSelectedVehicle() {
    final vehicle = selectedVehicle;
    if (vehicle == null) {
      return Future.value(const []);
    }
    return _documentService.remindersForVehicle(vehicle.id, asOf: _clock());
  }

  Future<MaintenanceReminder?> maintenanceReminderForItem(
    MaintenanceItem item,
  ) async {
    final current = await currentOdometerForVehicle(item.vehicleId);
    return _maintenanceItemService.reminderForItem(
      item,
      currentOdometer: current,
    );
  }

  Future<List<MaintenanceCompletion>> maintenanceHistoryForItem(
    MaintenanceItem item,
  ) {
    return _maintenanceItemService.completionHistoryForItem(
      item.vehicleId,
      item.id,
    );
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _busy = true;
    notifyListeners();

    try {
      _themeMode = _themeModeFromStorage(
        await _settingsRepository.getThemeMode(),
      );
      await _reloadData();
      _errorMessage = null;
    } catch (_) {
      _errorMessage = 'DriveTracker could not load your local data.';
    } finally {
      _initialized = true;
      _busy = false;
      notifyListeners();
    }
  }

  Future<Vehicle> addVehicle(VehicleDraft draft) async {
    return _runMutation(() async {
      final vehicle = await _vehicleService.addVehicle(draft);
      await _reloadData(preferredVehicleId: vehicle.id);
      return vehicle;
    });
  }

  Future<Vehicle> updateVehicle(String vehicleId, VehicleDraft draft) async {
    return _runMutation(() async {
      final vehicle = await _vehicleService.updateVehicle(vehicleId, draft);
      await _reloadData(preferredVehicleId: vehicle.id);
      return vehicle;
    });
  }

  Future<void> archiveVehicle(String vehicleId) async {
    return _runMutation(() async {
      await _vehicleService.archiveVehicle(vehicleId);
      await _reloadData();
    });
  }

  Future<void> selectVehicle(String vehicleId) async {
    return _runMutation(() async {
      final canSelect = _activeVehicles.any(
        (vehicle) => vehicle.id == vehicleId,
      );
      if (!canSelect) {
        throw const ValidationException(['Vehicle is not available.']);
      }
      await _settingsRepository.setSelectedVehicleId(vehicleId);
      await _reloadData(preferredVehicleId: vehicleId);
    });
  }

  OdometerAssessment assessOdometerUpdate(int reading) {
    return _odometerService.assessManualReading(
      currentOdometer: currentOdometer,
      newOdometer: reading,
    );
  }

  Future<OdometerEntry> updateOdometer(
    int reading, {
    bool allowHistorical = false,
    bool confirmLargeIncrease = false,
  }) async {
    final vehicle = selectedVehicle;
    if (vehicle == null) {
      throw const ValidationException([
        'Select a vehicle before updating mileage.',
      ]);
    }

    return _runMutation(() async {
      final entry = await _odometerService.recordManualReading(
        vehicleId: vehicle.id,
        odometer: reading,
        allowHistorical: allowHistorical,
        confirmLargeIncrease: confirmLargeIncrease,
      );
      await _reloadData(preferredVehicleId: vehicle.id);
      return entry;
    });
  }

  Future<RecordCategory> addCustomCategory({
    required RecordCategoryType type,
    required String name,
  }) async {
    return _runMutation(() {
      return _categoryService.createCustomCategory(type: type, name: name);
    });
  }

  Future<Refuel> addRefuel(
    RefuelDraft draft, {
    bool allowHistorical = false,
    bool confirmLargeIncrease = false,
  }) async {
    return _runMutation(() async {
      final refuel = await _refuelService.createRefuel(
        draft,
        allowHistorical: allowHistorical,
        confirmLargeIncrease: confirmLargeIncrease,
      );
      await _reloadData(preferredVehicleId: refuel.vehicleId);
      return refuel;
    });
  }

  Future<Refuel> updateRefuel(
    String refuelId,
    RefuelDraft draft, {
    bool allowHistorical = false,
    bool confirmLargeIncrease = false,
  }) async {
    return _runMutation(() async {
      final refuel = await _refuelService.updateRefuel(
        refuelId,
        draft,
        allowHistorical: allowHistorical,
        confirmLargeIncrease: confirmLargeIncrease,
      );
      await _reloadData(preferredVehicleId: refuel.vehicleId);
      return refuel;
    });
  }

  Future<void> deleteRefuel(String refuelId) async {
    return _runMutation(() async {
      final currentVehicleId = selectedVehicle?.id;
      await _refuelService.deleteRefuel(refuelId);
      await _reloadData(preferredVehicleId: currentVehicleId);
    });
  }

  Future<Expense> addExpense(
    ExpenseDraft draft, {
    bool allowHistorical = false,
    bool confirmLargeIncrease = false,
  }) async {
    return _runMutation(() async {
      final expense = await _expenseService.createExpense(
        draft,
        allowHistorical: allowHistorical,
        confirmLargeIncrease: confirmLargeIncrease,
      );
      await _reloadData(preferredVehicleId: expense.vehicleId);
      return expense;
    });
  }

  Future<Expense> updateExpense(
    String expenseId,
    ExpenseDraft draft, {
    bool allowHistorical = false,
    bool confirmLargeIncrease = false,
  }) async {
    return _runMutation(() async {
      final expense = await _expenseService.updateExpense(
        expenseId,
        draft,
        allowHistorical: allowHistorical,
        confirmLargeIncrease: confirmLargeIncrease,
      );
      await _reloadData(preferredVehicleId: expense.vehicleId);
      return expense;
    });
  }

  Future<void> deleteExpense(String expenseId) async {
    return _runMutation(() async {
      final currentVehicleId = selectedVehicle?.id;
      await _expenseService.deleteExpense(expenseId);
      await _reloadData(preferredVehicleId: currentVehicleId);
    });
  }

  Future<Income> addIncome(
    IncomeDraft draft, {
    bool allowHistorical = false,
    bool confirmLargeIncrease = false,
  }) async {
    return _runMutation(() async {
      final income = await _incomeService.createIncome(
        draft,
        allowHistorical: allowHistorical,
        confirmLargeIncrease: confirmLargeIncrease,
      );
      await _reloadData(preferredVehicleId: income.vehicleId);
      return income;
    });
  }

  Future<Income> updateIncome(
    String incomeId,
    IncomeDraft draft, {
    bool allowHistorical = false,
    bool confirmLargeIncrease = false,
  }) async {
    return _runMutation(() async {
      final income = await _incomeService.updateIncome(
        incomeId,
        draft,
        allowHistorical: allowHistorical,
        confirmLargeIncrease: confirmLargeIncrease,
      );
      await _reloadData(preferredVehicleId: income.vehicleId);
      return income;
    });
  }

  Future<void> deleteIncome(String incomeId) async {
    return _runMutation(() async {
      final currentVehicleId = selectedVehicle?.id;
      await _incomeService.deleteIncome(incomeId);
      await _reloadData(preferredVehicleId: currentVehicleId);
    });
  }

  Future<MaintenanceItem> addMaintenanceItem(
    MaintenanceItemDraft draft, {
    DateTime? baselineDateTime,
    int? baselineOdometer,
  }) async {
    return _runMutation(() async {
      final item = await _maintenanceItemService.createMaintenanceItem(draft);
      if (baselineDateTime != null || baselineOdometer != null) {
        await _serviceRecordService.createBaselineCompletion(
          item: item,
          eventDateTime: baselineDateTime ?? _clock(),
          odometer: baselineOdometer,
        );
      }
      await _reloadData(preferredVehicleId: item.vehicleId);
      return item;
    });
  }

  Future<MaintenanceItem> updateMaintenanceItem(
    String itemId,
    MaintenanceItemDraft draft,
  ) async {
    return _runMutation(() async {
      final item = await _maintenanceItemService.updateMaintenanceItem(
        itemId,
        draft,
      );
      await _reloadData(preferredVehicleId: item.vehicleId);
      return item;
    });
  }

  Future<void> archiveMaintenanceItem(String itemId) async {
    return _runMutation(() async {
      final item = await _maintenanceItemRepository.getById(itemId);
      await _maintenanceItemService.archiveMaintenanceItem(itemId);
      await _reloadData(preferredVehicleId: item?.vehicleId);
    });
  }

  Future<ServiceRecordWithItems> addServiceRecord(
    ServiceRecordDraft draft, {
    bool allowHistorical = false,
    bool confirmLargeIncrease = false,
  }) async {
    return _runMutation(() async {
      final service = await _serviceRecordService.createServiceRecord(
        draft,
        allowHistorical: allowHistorical,
        confirmLargeIncrease: confirmLargeIncrease,
      );
      await _reloadData(preferredVehicleId: service.record.vehicleId);
      return service;
    });
  }

  Future<ServiceRecordWithItems> updateServiceRecord(
    String serviceId,
    ServiceRecordDraft draft, {
    bool allowHistorical = false,
    bool confirmLargeIncrease = false,
  }) async {
    return _runMutation(() async {
      final service = await _serviceRecordService.updateServiceRecord(
        serviceId,
        draft,
        allowHistorical: allowHistorical,
        confirmLargeIncrease: confirmLargeIncrease,
      );
      await _reloadData(preferredVehicleId: service.record.vehicleId);
      return service;
    });
  }

  Future<void> deleteServiceRecord(String serviceId) async {
    return _runMutation(() async {
      final currentVehicleId = selectedVehicle?.id;
      await _serviceRecordService.deleteServiceRecord(serviceId);
      await _reloadData(preferredVehicleId: currentVehicleId);
    });
  }

  Future<VehicleDocument> addDocument(VehicleDocumentDraft draft) async {
    return _runMutation(() async {
      final document = await _documentService.createDocument(draft);
      await _reloadData(preferredVehicleId: document.vehicleId);
      return document;
    });
  }

  Future<VehicleDocument> updateDocument(
    String documentId,
    VehicleDocumentDraft draft,
  ) async {
    return _runMutation(() async {
      final document = await _documentService.updateDocument(documentId, draft);
      await _reloadData(preferredVehicleId: document.vehicleId);
      return document;
    });
  }

  Future<void> archiveDocument(String documentId) async {
    return _runMutation(() async {
      final document = await _documentRepository.getById(documentId);
      await _documentService.archiveDocument(documentId);
      await _reloadData(preferredVehicleId: document?.vehicleId);
    });
  }

  Future<VehicleDocument> renewDocument(
    String documentId,
    VehicleDocumentDraft draft,
  ) async {
    return _runMutation(() async {
      final document = await _documentService.renewDocument(documentId, draft);
      await _reloadData(preferredVehicleId: document.vehicleId);
      return document;
    });
  }

  Future<void> deleteDocumentPermanently(String documentId) async {
    return _runMutation(() async {
      final document = await _documentRepository.getById(documentId);
      await _documentService.deleteDocumentPermanently(documentId);
      await _reloadData(preferredVehicleId: document?.vehicleId);
    });
  }

  Future<Attachment?> pickAndAttach({
    required AttachmentParentType parentType,
    required String parentId,
  }) async {
    return _runMutation(() async {
      final attachment = await _attachmentService.pickAndAttach(
        parentType: parentType,
        parentId: parentId,
      );
      notifyListeners();
      return attachment;
    });
  }

  Future<Attachment> addAttachment({
    required AttachmentParentType parentType,
    required String parentId,
    required AttachmentSource source,
  }) async {
    return _runMutation(() async {
      final attachment = await _attachmentService.addAttachment(
        parentType: parentType,
        parentId: parentId,
        source: source,
      );
      notifyListeners();
      return attachment;
    });
  }

  Future<void> removeAttachment(String attachmentId) async {
    return _runMutation(() async {
      await _attachmentService.removeAttachment(attachmentId);
      notifyListeners();
    });
  }

  Future<AttachmentOpenResult> openAttachment(Attachment attachment) {
    return _attachmentService.openAttachment(attachment);
  }

  Future<bool> attachmentFileExists(Attachment attachment) {
    return _attachmentService.attachmentFileExists(attachment);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    return _runMutation(() async {
      _themeMode = mode;
      await _settingsRepository.setThemeMode(_themeModeToStorage(mode));
    });
  }

  Future<T> _runMutation<T>(Future<T> Function() action) async {
    _busy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      return await action();
    } on ValidationException catch (error) {
      _errorMessage = error.message;
      rethrow;
    } catch (_) {
      _errorMessage = 'Something went wrong. Please try again.';
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _reloadData({String? preferredVehicleId}) async {
    _activeVehicles = await _vehicleRepository.listActive();
    _archivedVehicles = await _vehicleRepository.listArchived();

    final selectedId =
        preferredVehicleId ?? await _settingsRepository.getSelectedVehicleId();
    final selected =
        _findActiveVehicle(selectedId) ??
        (_activeVehicles.isEmpty ? null : _activeVehicles.first);

    if (selected == null) {
      await _settingsRepository.setSelectedVehicleId(null);
      _dashboard = null;
      return;
    }

    if (selected.id != selectedId) {
      await _settingsRepository.setSelectedVehicleId(selected.id);
    }
    _dashboard = await _homeRepository.getVehicleDashboard(
      selected.id,
      now: _clock(),
    );
  }

  Vehicle? _findActiveVehicle(String? vehicleId) {
    if (vehicleId == null) {
      return null;
    }
    for (final vehicle in _activeVehicles) {
      if (vehicle.id == vehicleId) {
        return vehicle;
      }
    }
    return null;
  }

  ThemeMode _themeModeFromStorage(String? value) {
    switch (value) {
      case _themeLight:
        return ThemeMode.light;
      case _themeDark:
        return ThemeMode.dark;
      case _themeSystem:
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeToStorage(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return _themeLight;
      case ThemeMode.dark:
        return _themeDark;
      case ThemeMode.system:
        return _themeSystem;
    }
  }

  Future<bool> _attachmentParentExists(
    AttachmentParentType parentType,
    String parentId,
  ) async {
    return switch (parentType) {
      AttachmentParentType.document =>
        await _documentRepository.getById(parentId) != null,
      AttachmentParentType.refuel =>
        await _refuelRepository.getById(parentId) != null,
      AttachmentParentType.service =>
        await _serviceRecordRepository.getById(parentId) != null,
      AttachmentParentType.expense =>
        await _expenseRepository.getById(parentId) != null,
      AttachmentParentType.income =>
        await _incomeRepository.getById(parentId) != null,
      AttachmentParentType.vehicle =>
        await _vehicleRepository.getById(parentId) != null,
    };
  }
}
