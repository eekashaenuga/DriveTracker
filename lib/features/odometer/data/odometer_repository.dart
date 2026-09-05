import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/database/app_database.dart';
import '../domain/odometer_entry.dart';

class OdometerRepository {
  OdometerRepository(this._database);

  final AppDatabase _database;

  Future<void> insert(
    OdometerEntry entry, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.insert('odometer_entries', entry.toMap());
  }

  Future<void> update(
    OdometerEntry entry, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.update(
      'odometer_entries',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<OdometerEntry?> getBySource(
    OdometerSourceType sourceType,
    String sourceRecordId, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'odometer_entries',
      where: 'source_type = ? AND source_record_id = ?',
      whereArgs: [sourceType.storageValue, sourceRecordId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return OdometerEntry.fromMap(rows.first);
  }

  Future<void> deleteBySource(
    OdometerSourceType sourceType,
    String sourceRecordId, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.delete(
      'odometer_entries',
      where: 'source_type = ? AND source_record_id = ?',
      whereArgs: [sourceType.storageValue, sourceRecordId],
    );
  }

  Future<int?> currentOdometerForVehicle(
    String vehicleId, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.rawQuery(
      'SELECT MAX(odometer) AS current_odometer FROM odometer_entries WHERE vehicle_id = ?',
      [vehicleId],
    );
    final value = rows.first['current_odometer'];
    return value == null ? null : value as int;
  }

  Future<List<OdometerEntry>> recentForVehicle(
    String vehicleId, {
    int limit = 5,
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'odometer_entries',
      where: 'vehicle_id = ?',
      whereArgs: [vehicleId],
      orderBy: 'event_datetime DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(OdometerEntry.fromMap).toList();
  }

  Future<List<OdometerEntry>> allForVehicle(
    String vehicleId, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'odometer_entries',
      where: 'vehicle_id = ?',
      whereArgs: [vehicleId],
      orderBy: 'event_datetime DESC, created_at DESC',
    );
    return rows.map(OdometerEntry.fromMap).toList();
  }

  Future<sqflite.DatabaseExecutor> _executor(
    sqflite.DatabaseExecutor? executor,
  ) async {
    return executor ?? await _database.database;
  }
}
