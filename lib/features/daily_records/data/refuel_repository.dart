import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/database/app_database.dart';
import '../domain/refuel.dart';

class RefuelRepository {
  RefuelRepository(this._database);

  final AppDatabase _database;

  Future<void> insert(
    Refuel refuel, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.insert('refuels', refuel.toMap());
  }

  Future<void> update(
    Refuel refuel, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.update(
      'refuels',
      refuel.toMap(),
      where: 'id = ?',
      whereArgs: [refuel.id],
    );
  }

  Future<void> delete(String id, {sqflite.DatabaseExecutor? executor}) async {
    final db = await _executor(executor);
    await db.delete('refuels', where: 'id = ?', whereArgs: [id]);
  }

  Future<Refuel?> getById(
    String id, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'refuels',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Refuel.fromMap(rows.first);
  }

  Future<Refuel?> latestForVehicle(
    String vehicleId, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'refuels',
      where: 'vehicle_id = ?',
      whereArgs: [vehicleId],
      orderBy: 'event_datetime DESC, created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Refuel.fromMap(rows.first);
  }

  Future<List<Refuel>> listForVehicle(
    String vehicleId, {
    int? limit,
    bool ascending = false,
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'refuels',
      where: 'vehicle_id = ?',
      whereArgs: [vehicleId],
      orderBy: ascending
          ? 'event_datetime ASC, created_at ASC'
          : 'event_datetime DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(Refuel.fromMap).toList();
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
      SELECT COALESCE(SUM(total_cost_minor), 0) AS total
      FROM refuels
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
