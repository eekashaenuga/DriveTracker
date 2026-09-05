import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/database/app_database.dart';
import '../domain/income.dart';

class IncomeRepository {
  IncomeRepository(this._database);

  final AppDatabase _database;

  Future<void> insert(
    Income income, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.insert('income_records', income.toMap());
  }

  Future<void> update(
    Income income, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.update(
      'income_records',
      income.toMap(),
      where: 'id = ?',
      whereArgs: [income.id],
    );
  }

  Future<void> delete(String id, {sqflite.DatabaseExecutor? executor}) async {
    final db = await _executor(executor);
    await db.delete('income_records', where: 'id = ?', whereArgs: [id]);
  }

  Future<Income?> getById(
    String id, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'income_records',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Income.fromMap(rows.first);
  }

  Future<List<Income>> listForVehicle(
    String vehicleId, {
    int? limit,
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'income_records',
      where: 'vehicle_id = ?',
      whereArgs: [vehicleId],
      orderBy: 'event_datetime DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(Income.fromMap).toList();
  }

  Future<sqflite.DatabaseExecutor> _executor(
    sqflite.DatabaseExecutor? executor,
  ) async {
    return executor ?? await _database.database;
  }
}
