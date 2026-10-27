import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/database/app_database.dart';
import '../../../core/utilities/id_generator.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../attachments/domain/attachment.dart';
import '../../attachments/domain/attachment_service.dart';
import '../../odometer/data/odometer_repository.dart';
import '../../odometer/domain/odometer_entry.dart';
import '../../odometer/domain/odometer_policy.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../data/category_repository.dart';
import '../data/income_repository.dart';
import 'daily_record_validation.dart';
import 'income.dart';
import 'expense.dart';
import 'record_category.dart';

typedef Clock = DateTime Function();

class IncomeService {
  IncomeService({
    required this.database,
    required this.vehicleRepository,
    required this.categoryRepository,
    required this.odometerRepository,
    required this.incomeRepository,
    this.attachmentService,
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
  final AttachmentService? attachmentService;
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
      activity: draft.activity,
      source: DailyRecordValidation.cleanOptional(draft.source),
      notes: DailyRecordValidation.cleanOptional(draft.notes),
      createdAt: now,
      updatedAt: now,
    );

    await database.transaction((txn) async {
      await incomeRepository.insert(income, executor: txn);
      await _syncLinkedOdometer(income, now, executor: txn);
      await _saveCosts(income, draft, now, txn);
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
      originalCategoryId: existing.categoryId,
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
      activity: draft.activity,
      source: DailyRecordValidation.cleanOptional(draft.source),
      notes: DailyRecordValidation.cleanOptional(draft.notes),
      createdAt: existing.createdAt,
      updatedAt: now,
    );

    await database.transaction((txn) async {
      await incomeRepository.update(updated, executor: txn);
      await _syncLinkedOdometer(updated, now, executor: txn);
      await _saveCosts(updated, draft, now, txn);
    });
    return updated;
  }

  Future<void> _saveCosts(
    Income income,
    IncomeDraft draft,
    DateTime now,
    sqflite.DatabaseExecutor txn,
  ) async {
    final existing = await txn.query(
      'income_activity_expenses',
      where: 'income_id=?',
      whereArgs: [income.id],
    );
    final ids =
        draft.linkedExpenseIds ??
        existing.map((r) => r['expense_id'] as String).toList();
    if (ids.toSet().length != ids.length) {
      throw const ValidationException(['An expense can only be linked once.']);
    }
    if (income.activity.type.name == 'simple' &&
        (ids.isNotEmpty || draft.newDirectExpenses.isNotEmpty)) {
      throw const ValidationException([
        'Choose an activity template before linking direct costs.',
      ]);
    }
    for (final id in ids) {
      final rows = await txn.rawQuery(
        'SELECT e.vehicle_id,l.income_id FROM expenses e LEFT JOIN income_activity_expenses l ON l.expense_id=e.id WHERE e.id=?',
        [id],
      );
      if (rows.isEmpty ||
          rows.single['vehicle_id'] != income.vehicleId ||
          (rows.single['income_id'] != null &&
              rows.single['income_id'] != income.id)) {
        throw const ValidationException([
          'Select an unassigned expense from the same vehicle.',
        ]);
      }
    }
    final allIds = [...ids];
    for (final draftExpense in draft.newDirectExpenses) {
      // Canonical expense and relationship are committed with the income, never separately.
      final expense = Expense(
        id: _idGenerator.newId('expense'),
        vehicleId: income.vehicleId,
        categoryId: draftExpense.categoryId,
        eventDateTime: draftExpense.eventDateTime.toUtc(),
        amountMinor: draftExpense.amountMinor,
        merchant: DailyRecordValidation.cleanOptional(draftExpense.merchant),
        notes: DailyRecordValidation.cleanOptional(draftExpense.notes),
        paymentMethod: DailyRecordValidation.cleanOptional(
          draftExpense.paymentMethod,
        ),
        createdAt: now,
        updatedAt: now,
      );
      await txn.insert('expenses', expense.toMap());
      allIds.add(expense.id);
    }
    await txn.delete(
      'income_activity_expenses',
      where: 'income_id=?',
      whereArgs: [income.id],
    );
    for (final id in allIds) {
      await txn.insert('income_activity_expenses', {
        'income_id': income.id,
        'expense_id': id,
        'created_at': now.toIso8601String(),
      });
    }
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
    await attachmentService?.removeAttachmentsForParent(
      AttachmentParentType.income,
      existing.id,
    );
  }

  Future<void> _validateDraft(
    IncomeDraft draft, {
    String? originalCategoryId,
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
      originalCategoryId: originalCategoryId,
    );
    DailyRecordValidation.requirePositiveMoney(draft.amountMinor, 'Amount');
    draft.activity.validate(draft.amountMinor);
    for (final expense in draft.newDirectExpenses) {
      if (expense.vehicleId != draft.vehicleId || expense.odometer != null) {
        throw const ValidationException([
          'Direct expenses must use this vehicle and cannot add an odometer reading here.',
        ]);
      }
      DailyRecordValidation.requirePositiveMoney(
        expense.amountMinor,
        'Direct expense',
      );
      await DailyRecordValidation.requireCategory(
        repository: categoryRepository,
        categoryId: expense.categoryId,
        type: RecordCategoryType.expense,
      );
    }
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
