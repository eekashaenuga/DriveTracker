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
import '../data/expense_repository.dart';
import 'daily_record_validation.dart';
import 'expense.dart';
import 'record_category.dart';

typedef Clock = DateTime Function();

class ExpenseService {
  ExpenseService({
    required this.database,
    required this.vehicleRepository,
    required this.categoryRepository,
    required this.odometerRepository,
    required this.expenseRepository,
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
  final ExpenseRepository expenseRepository;
  final AttachmentService? attachmentService;
  final OdometerPolicy policy;
  final IdGenerator _idGenerator;
  final Clock _clock;

  Future<Expense> createExpense(
    ExpenseDraft draft, {
    bool allowHistorical = false,
    bool confirmLargeIncrease = false,
  }) async {
    await _validateDraft(
      draft,
      allowHistorical: allowHistorical,
      confirmLargeIncrease: confirmLargeIncrease,
    );

    final now = _clock().toUtc();
    final expense = Expense(
      id: _idGenerator.newId('expense'),
      vehicleId: draft.vehicleId,
      categoryId: draft.categoryId,
      eventDateTime: draft.eventDateTime.toUtc(),
      odometer: draft.odometer,
      amountMinor: draft.amountMinor,
      merchant: DailyRecordValidation.cleanOptional(draft.merchant),
      paymentMethod: DailyRecordValidation.cleanOptional(draft.paymentMethod),
      notes: DailyRecordValidation.cleanOptional(draft.notes),
      createdAt: now,
      updatedAt: now,
    );

    await database.transaction((txn) async {
      await expenseRepository.insert(expense, executor: txn);
      await _syncLinkedOdometer(expense, now, executor: txn);
    });
    return expense;
  }

  Future<Expense> updateExpense(
    String expenseId,
    ExpenseDraft draft, {
    bool allowHistorical = false,
    bool confirmLargeIncrease = false,
  }) async {
    final existing = await expenseRepository.getById(expenseId);
    if (existing == null) {
      throw const ValidationException(['Expense not found.']);
    }
    await _validateDraft(
      draft,
      allowHistorical: allowHistorical,
      confirmLargeIncrease: confirmLargeIncrease,
    );

    final now = _clock().toUtc();
    final updated = Expense(
      id: existing.id,
      vehicleId: draft.vehicleId,
      categoryId: draft.categoryId,
      eventDateTime: draft.eventDateTime.toUtc(),
      odometer: draft.odometer,
      amountMinor: draft.amountMinor,
      merchant: DailyRecordValidation.cleanOptional(draft.merchant),
      paymentMethod: DailyRecordValidation.cleanOptional(draft.paymentMethod),
      notes: DailyRecordValidation.cleanOptional(draft.notes),
      createdAt: existing.createdAt,
      updatedAt: now,
    );

    await database.transaction((txn) async {
      await expenseRepository.update(updated, executor: txn);
      await _syncLinkedOdometer(updated, now, executor: txn);
    });
    return updated;
  }

  Future<void> deleteExpense(String expenseId) async {
    final existing = await expenseRepository.getById(expenseId);
    if (existing == null) {
      return;
    }
    await database.transaction((txn) async {
      await odometerRepository.deleteBySource(
        OdometerSourceType.expense,
        existing.id,
        executor: txn,
      );
      await expenseRepository.delete(existing.id, executor: txn);
    });
    await attachmentService?.removeAttachmentsForParent(
      AttachmentParentType.expense,
      existing.id,
    );
  }

  Future<void> _validateDraft(
    ExpenseDraft draft, {
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
      type: RecordCategoryType.expense,
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
    Expense expense,
    DateTime now, {
    required sqflite.DatabaseExecutor executor,
  }) async {
    final existing = await odometerRepository.getBySource(
      OdometerSourceType.expense,
      expense.id,
      executor: executor,
    );
    final odometer = expense.odometer;
    if (odometer == null) {
      if (existing != null) {
        await odometerRepository.deleteBySource(
          OdometerSourceType.expense,
          expense.id,
          executor: executor,
        );
      }
      return;
    }

    final entry = OdometerEntry(
      id: existing?.id ?? _idGenerator.newId('odo'),
      vehicleId: expense.vehicleId,
      odometer: odometer,
      eventDateTime: expense.eventDateTime,
      sourceType: OdometerSourceType.expense,
      sourceRecordId: expense.id,
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
