import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/database/app_database.dart';
import '../domain/expense.dart';

class ExpenseRepository {
  ExpenseRepository(this._database);

  final AppDatabase _database;

  Future<void> insert(
    Expense expense, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.insert('expenses', expense.toMap());
  }

  Future<void> update(
    Expense expense, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.update(
      'expenses',
      expense.toMap(),
      where: 'id = ?',
      whereArgs: [expense.id],
    );
  }

  Future<void> delete(String id, {sqflite.DatabaseExecutor? executor}) async {
    final db = await _executor(executor);
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<Expense?> getById(
    String id, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'expenses',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Expense.fromMap(rows.first);
  }

  Future<List<Expense>> listForVehicle(
    String vehicleId, {
    int? limit,
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'expenses',
      where: 'vehicle_id = ?',
      whereArgs: [vehicleId],
      orderBy: 'event_datetime DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(Expense.fromMap).toList();
  }

  Future<int> spendingForVehicleBetween(
    String vehicleId, {
    required DateTime startInclusive,
    required DateTime endExclusive,
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount_minor), 0) AS total
      FROM expenses
      WHERE vehicle_id = ?
        AND event_datetime >= ?
        AND event_datetime < ?
      ''',
      [
        vehicleId,
        startInclusive.toUtc().toIso8601String(),
        endExclusive.toUtc().toIso8601String(),
      ],
    );
    return rows.first['total'] as int;
  }

  Future<sqflite.DatabaseExecutor> _executor(
    sqflite.DatabaseExecutor? executor,
  ) async {
    return executor ?? await _database.database;
  }
}
