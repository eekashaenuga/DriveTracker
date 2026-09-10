import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/database/app_database.dart';
import '../../../core/utilities/id_generator.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../attachments/domain/attachment.dart';
import '../../attachments/domain/attachment_service.dart';
import '../../daily_records/domain/daily_record_validation.dart';
import '../../odometer/data/odometer_repository.dart';
import '../../odometer/domain/odometer_entry.dart';
import '../../odometer/domain/odometer_policy.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../data/maintenance_item_repository.dart';
import '../data/service_record_repository.dart';
import 'maintenance_item.dart';
import 'service_record.dart';

typedef Clock = DateTime Function();

class ServiceRecordService {
  ServiceRecordService({
    required this.database,
    required this.vehicleRepository,
    required this.maintenanceItemRepository,
    required this.odometerRepository,
    required this.serviceRecordRepository,
    this.attachmentService,
    this.policy = const OdometerPolicy(),
    IdGenerator? idGenerator,
    Clock? clock,
  }) : _idGenerator = idGenerator ?? IdGenerator(),
       _clock = clock ?? (() => DateTime.now().toUtc());

  final AppDatabase database;
  final VehicleRepository vehicleRepository;
  final MaintenanceItemRepository maintenanceItemRepository;
  final OdometerRepository odometerRepository;
  final ServiceRecordRepository serviceRecordRepository;
  final AttachmentService? attachmentService;
  final OdometerPolicy policy;
  final IdGenerator _idGenerator;
  final Clock _clock;

  Future<ServiceRecordWithItems> createServiceRecord(
    ServiceRecordDraft draft, {
    bool allowHistorical = false,
    bool confirmLargeIncrease = false,
  }) async {
    final cleanItems = await _validateDraft(
      draft,
      allowHistorical: allowHistorical,
      confirmLargeIncrease: confirmLargeIncrease,
    );

    final now = _clock().toUtc();
    final record = ServiceRecord(
      id: _idGenerator.newId('service'),
      vehicleId: draft.vehicleId,
      eventDateTime: draft.eventDateTime.toUtc(),
      odometer: draft.odometer,
      totalCostMinor: draft.totalCostMinor,
      garage: DailyRecordValidation.cleanOptional(draft.garage),
      notes: DailyRecordValidation.cleanOptional(draft.notes),
      isBaseline: draft.isBaseline,
      createdAt: now,
      updatedAt: now,
    );
    final items = _serviceItems(record.id, cleanItems, now);

    await database.transaction((txn) async {
      await serviceRecordRepository.insertRecord(record, executor: txn);
      for (final item in items) {
        await serviceRecordRepository.insertItem(item, executor: txn);
      }
      await _syncLinkedOdometer(record, now, executor: txn);
    });
    return ServiceRecordWithItems(record: record, items: items);
  }

  Future<ServiceRecordWithItems> createBaselineCompletion({
    required MaintenanceItem item,
    required DateTime eventDateTime,
    int? odometer,
  }) {
    return createServiceRecord(
      ServiceRecordDraft(
        vehicleId: item.vehicleId,
        eventDateTime: eventDateTime,
        odometer: odometer,
        totalCostMinor: 0,
        garage: 'Baseline',
        notes: 'Imported maintenance baseline.',
        isBaseline: true,
        items: [
          ServiceItemDraft(maintenanceItemId: item.id, itemName: item.name),
        ],
      ),
      allowHistorical: true,
      confirmLargeIncrease: true,
    );
  }

  Future<ServiceRecordWithItems> updateServiceRecord(
    String serviceId,
    ServiceRecordDraft draft, {
    bool allowHistorical = false,
    bool confirmLargeIncrease = false,
  }) async {
    final existing = await serviceRecordRepository.getById(serviceId);
    if (existing == null) {
      throw const ValidationException(['Service record not found.']);
    }
    final cleanItems = await _validateDraft(
      draft,
      allowHistorical: allowHistorical,
      confirmLargeIncrease: confirmLargeIncrease,
    );

    final now = _clock().toUtc();
    final updated = ServiceRecord(
      id: existing.id,
      vehicleId: draft.vehicleId,
      eventDateTime: draft.eventDateTime.toUtc(),
      odometer: draft.odometer,
      totalCostMinor: draft.totalCostMinor,
      garage: DailyRecordValidation.cleanOptional(draft.garage),
      notes: DailyRecordValidation.cleanOptional(draft.notes),
      isBaseline: draft.isBaseline,
      createdAt: existing.createdAt,
      updatedAt: now,
    );
    final items = _serviceItems(updated.id, cleanItems, now);

    await database.transaction((txn) async {
      await serviceRecordRepository.updateRecord(updated, executor: txn);
      await serviceRecordRepository.replaceItemsForService(
        updated.id,
        items,
        executor: txn,
      );
      await _syncLinkedOdometer(updated, now, executor: txn);
    });
    return ServiceRecordWithItems(record: updated, items: items);
  }

  Future<void> deleteServiceRecord(String serviceId) async {
    final existing = await serviceRecordRepository.getById(serviceId);
    if (existing == null) {
      return;
    }

    await database.transaction((txn) async {
      await odometerRepository.deleteBySource(
        OdometerSourceType.service,
        existing.id,
        executor: txn,
      );
      await serviceRecordRepository.deleteRecord(existing.id, executor: txn);
    });
    await attachmentService?.removeAttachmentsForParent(
      AttachmentParentType.service,
      existing.id,
    );
  }

  Future<List<ServiceItemDraft>> _validateDraft(
    ServiceRecordDraft draft, {
    required bool allowHistorical,
    required bool confirmLargeIncrease,
  }) async {
    await DailyRecordValidation.requireActiveVehicle(
      vehicleRepository,
      draft.vehicleId,
    );
    if (!draft.isBaseline && draft.odometer == null) {
      throw const ValidationException(['Service odometer is required.']);
    }
    if (draft.odometer != null && draft.odometer! < 0) {
      throw const ValidationException([
        'Odometer readings cannot be negative.',
      ]);
    }
    if (draft.totalCostMinor < 0) {
      throw const ValidationException(['Service total cannot be negative.']);
    }
    if (draft.isBaseline && draft.totalCostMinor != 0) {
      throw const ValidationException([
        'Baseline maintenance history must not carry spending.',
      ]);
    }
    if (draft.items.isEmpty) {
      throw const ValidationException(['Add at least one service item.']);
    }

    final cleanItems = <ServiceItemDraft>[];
    for (final item in draft.items) {
      cleanItems.add(await _cleanServiceItem(draft.vehicleId, item));
    }
    if (cleanItems.isEmpty) {
      throw const ValidationException(['Add at least one service item.']);
    }

    await _assessOdometer(
      draft.vehicleId,
      draft.odometer,
      allowHistorical: allowHistorical,
      confirmLargeIncrease: confirmLargeIncrease,
    );
    return cleanItems;
  }

  Future<ServiceItemDraft> _cleanServiceItem(
    String vehicleId,
    ServiceItemDraft draft,
  ) async {
    final maintenanceItemId = DailyRecordValidation.cleanOptional(
      draft.maintenanceItemId,
    );
    var cleanName = draft.itemName.trim();
    if (maintenanceItemId != null) {
      final maintenanceItem = await maintenanceItemRepository.getById(
        maintenanceItemId,
      );
      if (maintenanceItem == null || maintenanceItem.vehicleId != vehicleId) {
        throw const ValidationException([
          'Select a valid maintenance item for this vehicle.',
        ]);
      }
      if (cleanName.isEmpty) {
        cleanName = maintenanceItem.name;
      }
    }
    if (cleanName.isEmpty) {
      throw const ValidationException(['Service item name is required.']);
    }
    final allocatedCost = draft.allocatedCostMinor;
    if (allocatedCost != null && allocatedCost < 0) {
      throw const ValidationException([
        'Allocated item cost cannot be negative.',
      ]);
    }
    return ServiceItemDraft(
      maintenanceItemId: maintenanceItemId,
      itemName: cleanName,
      allocatedCostMinor: allocatedCost,
      notes: DailyRecordValidation.cleanOptional(draft.notes),
    );
  }

  Future<void> _assessOdometer(
    String vehicleId,
    int? odometer, {
    required bool allowHistorical,
    required bool confirmLargeIncrease,
  }) async {
    if (odometer == null) {
      return;
    }
    final current = await odometerRepository.currentOdometerForVehicle(
      vehicleId,
    );
    final assessment = policy.assess(
      currentOdometer: current,
      newOdometer: odometer,
    );
    switch (assessment.decision) {
      case OdometerDecision.invalid:
        throw ValidationException([assessment.message]);
      case OdometerDecision.belowCurrent:
        if (!allowHistorical) {
          throw OdometerConfirmationRequired(assessment);
        }
        break;
      case OdometerDecision.unusuallyLargeIncrease:
        if (!confirmLargeIncrease) {
          throw OdometerConfirmationRequired(assessment);
        }
        break;
      case OdometerDecision.accepted:
        break;
    }
  }

  List<ServiceItem> _serviceItems(
    String serviceId,
    List<ServiceItemDraft> drafts,
    DateTime now,
  ) {
    return [
      for (final draft in drafts)
        ServiceItem(
          id: _idGenerator.newId('service_item'),
          serviceId: serviceId,
          maintenanceItemId: draft.maintenanceItemId,
          itemName: draft.itemName,
          allocatedCostMinor: draft.allocatedCostMinor,
          notes: draft.notes,
          createdAt: now,
          updatedAt: now,
        ),
    ];
  }

  Future<void> _syncLinkedOdometer(
    ServiceRecord record,
    DateTime now, {
    required sqflite.DatabaseExecutor executor,
  }) async {
    final existing = await odometerRepository.getBySource(
      OdometerSourceType.service,
      record.id,
      executor: executor,
    );
    final odometer = record.odometer;
    if (odometer == null) {
      if (existing != null) {
        await odometerRepository.deleteBySource(
          OdometerSourceType.service,
          record.id,
          executor: executor,
        );
      }
      return;
    }

    final entry = OdometerEntry(
      id: existing?.id ?? _idGenerator.newId('odo'),
      vehicleId: record.vehicleId,
      odometer: odometer,
      eventDateTime: record.eventDateTime,
      sourceType: OdometerSourceType.service,
      sourceRecordId: record.id,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    if (existing == null) {
      await odometerRepository.insert(entry, executor: executor);
    } else {
      await odometerRepository.update(entry, executor: executor);
    }
  }
}
