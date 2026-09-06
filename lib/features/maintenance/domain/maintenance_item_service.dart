import '../../../core/utilities/id_generator.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../daily_records/domain/daily_record_validation.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../data/maintenance_item_repository.dart';
import '../data/service_record_repository.dart';
import 'maintenance_item.dart';
import 'maintenance_reminder.dart';
import 'maintenance_reminder_engine.dart';
import 'service_record.dart';

typedef Clock = DateTime Function();

class MaintenanceItemService {
  MaintenanceItemService({
    required this.vehicleRepository,
    required this.maintenanceItemRepository,
    required this.serviceRecordRepository,
    MaintenanceReminderEngine? reminderEngine,
    IdGenerator? idGenerator,
    Clock? clock,
  }) : _reminderEngine = reminderEngine ?? const MaintenanceReminderEngine(),
       _idGenerator = idGenerator ?? IdGenerator(),
       _clock = clock ?? (() => DateTime.now().toUtc());

  final VehicleRepository vehicleRepository;
  final MaintenanceItemRepository maintenanceItemRepository;
  final ServiceRecordRepository serviceRecordRepository;
  final MaintenanceReminderEngine _reminderEngine;
  final IdGenerator _idGenerator;
  final Clock _clock;

  Future<MaintenanceItem> createMaintenanceItem(
    MaintenanceItemDraft draft,
  ) async {
    await _validateDraft(draft);
    final cleanName = draft.name.trim();
    final duplicate = await maintenanceItemRepository.findActiveByName(
      draft.vehicleId,
      cleanName,
    );
    if (duplicate != null) {
      throw ValidationException([
        'A maintenance item named "$cleanName" already exists.',
      ]);
    }

    final now = _clock().toUtc();
    final item = MaintenanceItem(
      id: _idGenerator.newId('maint'),
      vehicleId: draft.vehicleId,
      name: cleanName,
      category: DailyRecordValidation.cleanOptional(draft.category),
      mileageInterval: draft.mileageInterval,
      timeIntervalDays: draft.timeIntervalDays,
      mileageWarning: draft.mileageWarning,
      dateWarningDays: draft.dateWarningDays,
      reminderEnabled: draft.reminderEnabled,
      isArchived: false,
      createdAt: now,
      updatedAt: now,
    );
    await maintenanceItemRepository.insert(item);
    return item;
  }

  Future<MaintenanceItem> updateMaintenanceItem(
    String itemId,
    MaintenanceItemDraft draft,
  ) async {
    final existing = await maintenanceItemRepository.getById(itemId);
    if (existing == null) {
      throw const ValidationException(['Maintenance item not found.']);
    }
    await _validateDraft(draft);
    final cleanName = draft.name.trim();
    final duplicate = await maintenanceItemRepository.findActiveByName(
      draft.vehicleId,
      cleanName,
      excludingId: itemId,
    );
    if (duplicate != null) {
      throw ValidationException([
        'A maintenance item named "$cleanName" already exists.',
      ]);
    }

    final updated = MaintenanceItem(
      id: existing.id,
      vehicleId: draft.vehicleId,
      name: cleanName,
      category: DailyRecordValidation.cleanOptional(draft.category),
      mileageInterval: draft.mileageInterval,
      timeIntervalDays: draft.timeIntervalDays,
      mileageWarning: draft.mileageWarning,
      dateWarningDays: draft.dateWarningDays,
      reminderEnabled: draft.reminderEnabled,
      isArchived: existing.isArchived,
      createdAt: existing.createdAt,
      updatedAt: _clock().toUtc(),
    );
    await maintenanceItemRepository.update(updated);
    return updated;
  }

  Future<void> archiveMaintenanceItem(String itemId) async {
    final existing = await maintenanceItemRepository.getById(itemId);
    if (existing == null || existing.isArchived) {
      return;
    }
    await maintenanceItemRepository.archive(itemId, _clock().toUtc());
  }

  Future<List<MaintenanceReminder>> remindersForVehicle(
    String vehicleId, {
    required int? currentOdometer,
    DateTime? asOf,
  }) async {
    final items = await maintenanceItemRepository.listForVehicle(vehicleId);
    final reminders = <MaintenanceReminder>[];
    for (final item in items) {
      final completions = await serviceRecordRepository
          .completionsForMaintenanceItem(vehicleId, item.id);
      reminders.add(
        _reminderEngine.evaluate(
          item: item,
          completions: completions,
          currentOdometer: currentOdometer,
          asOf: asOf ?? _clock(),
        ),
      );
    }
    return _reminderEngine.sortByUrgency(reminders);
  }

  Future<MaintenanceReminder?> mostUrgentReminderForVehicle(
    String vehicleId, {
    required int? currentOdometer,
    DateTime? asOf,
  }) async {
    final reminders = await remindersForVehicle(
      vehicleId,
      currentOdometer: currentOdometer,
      asOf: asOf,
    );
    return _reminderEngine.mostUrgent(reminders);
  }

  Future<MaintenanceReminder> reminderForItem(
    MaintenanceItem item, {
    required int? currentOdometer,
    DateTime? asOf,
  }) async {
    final completions = await serviceRecordRepository
        .completionsForMaintenanceItem(item.vehicleId, item.id);
    return _reminderEngine.evaluate(
      item: item,
      completions: completions,
      currentOdometer: currentOdometer,
      asOf: asOf ?? _clock(),
    );
  }

  Future<List<MaintenanceCompletion>> completionHistoryForItem(
    String vehicleId,
    String itemId,
  ) {
    return serviceRecordRepository.completionsForMaintenanceItem(
      vehicleId,
      itemId,
    );
  }

  Future<void> _validateDraft(MaintenanceItemDraft draft) async {
    await DailyRecordValidation.requireActiveVehicle(
      vehicleRepository,
      draft.vehicleId,
    );
    if (draft.name.trim().isEmpty) {
      throw const ValidationException(['Maintenance item name is required.']);
    }
    if (draft.mileageInterval != null && draft.mileageInterval! <= 0) {
      throw const ValidationException([
        'Mileage interval must be greater than zero.',
      ]);
    }
    if (draft.timeIntervalDays != null && draft.timeIntervalDays! <= 0) {
      throw const ValidationException([
        'Time interval must be greater than zero.',
      ]);
    }
    if (draft.mileageWarning < 0) {
      throw const ValidationException(['Mileage warning cannot be negative.']);
    }
    if (draft.dateWarningDays < 0) {
      throw const ValidationException(['Date warning cannot be negative.']);
    }
  }
}
