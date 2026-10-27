import '../../../core/database/app_database.dart';
import '../domain/expense.dart';
import '../domain/income.dart';
import '../domain/income_earnings.dart';

class IncomeActivityExpenseRepository {
  IncomeActivityExpenseRepository(this.database);
  final AppDatabase database;
  Future<List<Expense>> linked(String incomeId) async {
    final db = await database.database;
    final rows = await db.rawQuery(
      'SELECT e.* FROM expenses e JOIN income_activity_expenses l ON l.expense_id=e.id WHERE l.income_id=? ORDER BY e.event_datetime DESC,e.id',
      [incomeId],
    );
    return rows.map(Expense.fromMap).toList();
  }

  Future<List<Expense>> available(String vehicleId, String? incomeId) async {
    final db = await database.database;
    final rows = await db.rawQuery(
      'SELECT e.* FROM expenses e LEFT JOIN income_activity_expenses l ON l.expense_id=e.id WHERE e.vehicle_id=? AND (l.income_id IS NULL OR l.income_id=?) ORDER BY e.event_datetime DESC,e.id',
      [vehicleId, incomeId],
    );
    return rows.map(Expense.fromMap).toList();
  }

  Future<IncomeEarnings> earnings(Income income) async => IncomeEarnings(
    income,
    (await linked(income.id)).fold<int>(0, (s, e) => s + e.amountMinor),
  );
}
