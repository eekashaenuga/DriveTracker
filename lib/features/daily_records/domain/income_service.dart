import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/database/app_database.dart';
import '../../../core/utilities/id_generator.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../odometer/data/odometer_repository.dart';
import '../../odometer/domain/odometer_entry.dart';
import '../../odometer/domain/odometer_policy.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../data/category_repository.dart';
import '../data/income_repository.dart';
import 'daily_record_validation.dart';
import 'income.dart';
import 'record_category.dart';

typedef Clock = DateTime Function();

class IncomeService {
  IncomeService({
    required this.database,
    required this.vehicleRepository,
    required this.categoryRepository,
    required this.odometerRepository,
    required this.incomeRepository,
    this.policy = const OdometerPolicy(),
    IdGenerator? idGenerator,
    Clock? clock,
  }) : _idGenerator = idGenerator ?? IdGenerator(),
       _clock = clock ?? (() => DateTime.now().toUtc());

  final AppDatabase database;
  final VehicleRepository vehicleRepository;
  final CategoryRepository categoryRepository;
  final OdometerRepository odometerRepository;
  final IncomeRepository incomeRepository;
  final OdometerPolicy policy;
  final IdGenerator _idGenerator;
  final Clock _clock;

  Future<Income> createIncome(
    IncomeDraft draft, {
    bool allowHistorical = false,
    bool confirmLargeIncrease = false,
  }) async {
    await _validateDraft(
      draft,
      allowHistorical: allowHistorical,
      confirmLargeIncrease: confirmLargeIncrease,
    );

    final now = _clock().toUtc();
    final income = Income(
      id: _idGenerator.newId('income'),
      vehicleId: draft.vehicleId,
      categoryId: draft.categoryId,
      eventDateTime: draft.eventDateTime.toUtc(),
      odometer: draft.odometer,
      amountMinor: draft.amountMinor,
      source: DailyRecordValidation.cleanOptional(draft.source),
      notes: DailyRecordValidation.cleanOptional(draft.notes),
      createdAt: now,
      updatedAt: now,
    );

    await database.transaction((txn) async {
      await incomeRepository.insert(income, executor: txn);
      await _syncLinkedOdometer(income, now, executor: txn);
    });
    return income;
  }

  Future<Income> updateIncome(
    String incomeId,
    IncomeDraft draft, {
    bool allowHistorical = false,
    bool confirmLargeIncrease = false,
  }) async {
    final existing = await incomeRepository.getById(incomeId);
    if (existing == null) {
      throw const ValidationException(['Income not found.']);
    }
    await _validateDraft(
      draft,
      allowHistorical: allowHistorical,
      confirmLargeIncrease: confirmLargeIncrease,
    );

    final now = _clock().toUtc();
    final updated = Income(
      id: existing.id,
      vehicleId: draft.vehicleId,
      categoryId: draft.categoryId,
      eventDateTime: draft.eventDateTime.toUtc(),
      odometer: draft.odometer,
      amountMinor: draft.amountMinor,
      source: DailyRecordValidation.cleanOptional(draft.source),
      notes: DailyRecordValidation.cleanOptional(draft.notes),
      createdAt: existing.createdAt,
      updatedAt: now,
    );

    await database.transaction((txn) async {
      await incomeRepository.update(updated, executor: txn);
      await _syncLinkedOdometer(updated, now, executor: txn);
    });
    return updated;
  }

  Future<void> deleteIncome(String incomeId) async {
    final existing = await incomeRepository.getById(incomeId);
    if (existing == null) {
      return;
    }
    await database.transaction((txn) async {
      await odometerRepository.deleteBySource(
        OdometerSourceType.income,
        existing.id,
        executor: txn,
      );
      await incomeRepository.delete(existing.id, executor: txn);
    });
  }

  Future<void> _validateDraft(
    IncomeDraft draft, {
    required bool allowHistorical,
    required bool confirmLargeIncrease,
  }) async {
    await DailyRecordValidation.requireActiveVehicle(
      vehicleRepository,
      draft.vehicleId,
    );
    await DailyRecordValidation.requireCategory(
      repository: categoryRepository,
      categoryId: draft.categoryId,
      type: RecordCategoryType.income,
    );
    DailyRecordValidation.requirePositiveMoney(draft.amountMinor, 'Amount');
    DailyRecordValidation.requireOptionalOdometer(draft.odometer);
    await _assessOptionalOdometer(
      draft.vehicleId,
      draft.odometer,
      allowHistorical: allowHistorical,
      confirmLargeIncrease: confirmLargeIncrease,
    );
  }

  Future<void> _assessOptionalOdometer(
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

  Future<void> _syncLinkedOdometer(
    Income income,
    DateTime now, {
    required sqflite.DatabaseExecutor executor,
  }) async {
    final existing = await odometerRepository.getBySource(
      OdometerSourceType.income,
      income.id,
      executor: executor,
    );
    final odometer = income.odometer;
    if (odometer == null) {
      if (existing != null) {
        await odometerRepository.deleteBySource(
          OdometerSourceType.income,
          income.id,
          executor: executor,
        );
      }
      return;
    }

    final entry = OdometerEntry(
      id: existing?.id ?? _idGenerator.newId('odo'),
      vehicleId: income.vehicleId,
      odometer: odometer,
      eventDateTime: income.eventDateTime,
      sourceType: OdometerSourceType.income,
      sourceRecordId: income.id,
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
