import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/database/app_database.dart';
import '../domain/vehicle.dart';

class VehicleRepository {
  VehicleRepository(this._database);

  final AppDatabase _database;

  Future<void> insert(
    Vehicle vehicle, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.insert('vehicles', vehicle.toMap());
  }

  Future<void> update(
    Vehicle vehicle, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.update(
      'vehicles',
      vehicle.toMap(),
      where: 'id = ?',
      whereArgs: [vehicle.id],
    );
  }

  Future<void> archive(
    String vehicleId,
    DateTime updatedAt, {
    sqflite.DatabaseExecutor? executor,
  }) {
    return setArchived(vehicleId, true, updatedAt, executor: executor);
  }

  Future<void> restore(
    String vehicleId,
    DateTime updatedAt, {
    sqflite.DatabaseExecutor? executor,
  }) {
    return setArchived(vehicleId, false, updatedAt, executor: executor);
  }

  Future<void> setArchived(
    String vehicleId,
    bool isArchived,
    DateTime updatedAt, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.update(
      'vehicles',
      {
        'is_archived': isArchived ? 1 : 0,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [vehicleId],
    );
  }

  Future<Vehicle?> getById(
    String id, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'vehicles',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Vehicle.fromMap(rows.first);
  }

  Future<List<Vehicle>> listActive({sqflite.DatabaseExecutor? executor}) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'vehicles',
      where: 'is_archived = ?',
      whereArgs: [0],
      orderBy: 'created_at DESC',
    );
    return rows.map(Vehicle.fromMap).toList();
  }

  Future<List<Vehicle>> listArchived({
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'vehicles',
      where: 'is_archived = ?',
      whereArgs: [1],
      orderBy: 'updated_at DESC',
    );
    return rows.map(Vehicle.fromMap).toList();
  }

  Future<bool> hasAnyVehicles({sqflite.DatabaseExecutor? executor}) async {
    final db = await _executor(executor);
    final rows = await db.query('vehicles', columns: ['id'], limit: 1);
    return rows.isNotEmpty;
  }

  Future<sqflite.DatabaseExecutor> _executor(
    sqflite.DatabaseExecutor? executor,
  ) async {
    return executor ?? await _database.database;
  }
}
