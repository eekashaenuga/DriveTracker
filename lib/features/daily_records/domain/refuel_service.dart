import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/database/app_database.dart';
import '../../../core/utilities/id_generator.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../odometer/data/odometer_repository.dart';
import '../../odometer/domain/odometer_entry.dart';
import '../../odometer/domain/odometer_policy.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../data/refuel_repository.dart';
import 'daily_record_validation.dart';
import 'fuel_entry_calculator.dart';
import 'refuel.dart';

typedef Clock = DateTime Function();

class RefuelService {
  RefuelService({
    required this.database,
    required this.vehicleRepository,
    required this.odometerRepository,
    required this.refuelRepository,
    this.policy = const OdometerPolicy(),
    IdGenerator? idGenerator,
    Clock? clock,
  }) : _idGenerator = idGenerator ?? IdGenerator(),
       _clock = clock ?? (() => DateTime.now().toUtc());

  final AppDatabase database;
  final VehicleRepository vehicleRepository;
  final OdometerRepository odometerRepository;
  final RefuelRepository refuelRepository;
  final OdometerPolicy policy;
  final IdGenerator _idGenerator;
  final Clock _clock;

  Future<Refuel> createRefuel(
    RefuelDraft draft, {
    bool allowHistorical = false,
    bool confirmLargeIncrease = false,
  }) async {
    await _validateDraft(
      draft,
      allowHistorical: allowHistorical,
      confirmLargeIncrease: confirmLargeIncrease,
    );

    final now = _clock().toUtc();
    final refuel = Refuel(
      id: _idGenerator.newId('refuel'),
      vehicleId: draft.vehicleId,
      eventDateTime: draft.eventDateTime.toUtc(),
      odometer: draft.odometer,
      fuelType: draft.fuelType,
      totalCostMinor: draft.totalCostMinor,
      volumeMillilitres: draft.volumeMillilitres,
      unitPriceMicrosPerLitre: draft.unitPriceMicrosPerLitre,
      isFullTank: draft.isFullTank,
      missedPreviousRefuel: draft.missedPreviousRefuel,
      station: DailyRecordValidation.cleanOptional(draft.station),
      notes: DailyRecordValidation.cleanOptional(draft.notes),
      createdAt: now,
      updatedAt: now,
    );

    await database.transaction((txn) async {
      await refuelRepository.insert(refuel, executor: txn);
      await _upsertLinkedOdometer(refuel, now, executor: txn);
    });
    return refuel;
  }

  Future<Refuel> updateRefuel(
    String refuelId,
    RefuelDraft draft, {
    bool allowHistorical = false,
    bool confirmLargeIncrease = false,
  }) async {
    final existing = await refuelRepository.getById(refuelId);
    if (existing == null) {
      throw const ValidationException(['Refuel not found.']);
    }
    await _validateDraft(
      draft,
      allowHistorical: allowHistorical,
      confirmLargeIncrease: confirmLargeIncrease,
    );

    final now = _clock().toUtc();
    final updated = Refuel(
      id: existing.id,
      vehicleId: draft.vehicleId,
      eventDateTime: draft.eventDateTime.toUtc(),
      odometer: draft.odometer,
      fuelType: draft.fuelType,
      totalCostMinor: draft.totalCostMinor,
      volumeMillilitres: draft.volumeMillilitres,
      unitPriceMicrosPerLitre: draft.unitPriceMicrosPerLitre,
      isFullTank: draft.isFullTank,
      missedPreviousRefuel: draft.missedPreviousRefuel,
      station: DailyRecordValidation.cleanOptional(draft.station),
      notes: DailyRecordValidation.cleanOptional(draft.notes),
      createdAt: existing.createdAt,
      updatedAt: now,
    );

    await database.transaction((txn) async {
      await refuelRepository.update(updated, executor: txn);
      await _upsertLinkedOdometer(updated, now, executor: txn);
    });
    return updated;
  }

  Future<void> deleteRefuel(String refuelId) async {
    final existing = await refuelRepository.getById(refuelId);
    if (existing == null) {
      return;
    }

    await database.transaction((txn) async {
      await odometerRepository.deleteBySource(
        OdometerSourceType.refuel,
        existing.id,
        executor: txn,
      );
      await refuelRepository.delete(existing.id, executor: txn);
    });
  }

  Future<void> _validateDraft(
    RefuelDraft draft, {
    required bool allowHistorical,
    required bool confirmLargeIncrease,
  }) async {
    await DailyRecordValidation.requireActiveVehicle(
      vehicleRepository,
      draft.vehicleId,
    );
    if (draft.odometer < 0) {
      throw const ValidationException([
        'Odometer readings cannot be negative.',
      ]);
    }
    if (draft.totalCostMinor <= 0) {
      throw const ValidationException([
        'Total cost must be greater than zero.',
      ]);
    }
    if (draft.volumeMillilitres <= 0) {
      throw const ValidationException([
        'Fuel volume must be greater than zero.',
      ]);
    }
    if (draft.unitPriceMicrosPerLitre <= 0) {
      throw const ValidationException([
        'Unit price must be greater than zero.',
      ]);
    }
    final values = FuelEntryValues(
      totalCostMinor: draft.totalCostMinor,
      volumeMillilitres: draft.volumeMillilitres,
      unitPriceMicrosPerLitre: draft.unitPriceMicrosPerLitre,
    );
    if (!FuelEntryCalculator.isConsistent(values)) {
      throw const ValidationException([
        'Fuel cost, volume and unit price do not match.',
      ]);
    }

    final current = await odometerRepository.currentOdometerForVehicle(
      draft.vehicleId,
    );
    final assessment = policy.assess(
      currentOdometer: current,
      newOdometer: draft.odometer,
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

  Future<void> _upsertLinkedOdometer(
    Refuel refuel,
    DateTime now, {
    required sqflite.DatabaseExecutor executor,
  }) async {
    final existing = await odometerRepository.getBySource(
      OdometerSourceType.refuel,
      refuel.id,
      executor: executor,
    );
    final entry = OdometerEntry(
      id: existing?.id ?? _idGenerator.newId('odo'),
      vehicleId: refuel.vehicleId,
      odometer: refuel.odometer,
      eventDateTime: refuel.eventDateTime,
      sourceType: OdometerSourceType.refuel,
      sourceRecordId: refuel.id,
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
