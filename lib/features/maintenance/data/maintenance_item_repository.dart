import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/database/app_database.dart';
import '../domain/maintenance_item.dart';

class MaintenanceItemRepository {
  MaintenanceItemRepository(this._database);

  final AppDatabase _database;

  Future<void> insert(
    MaintenanceItem item, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.insert('maintenance_items', item.toMap());
  }

  Future<void> update(
    MaintenanceItem item, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.update(
      'maintenance_items',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<MaintenanceItem?> getById(
    String id, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'maintenance_items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return MaintenanceItem.fromMap(rows.first);
  }

  Future<List<MaintenanceItem>> listForVehicle(
    String vehicleId, {
    bool includeArchived = false,
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'maintenance_items',
      where: includeArchived
          ? 'vehicle_id = ?'
          : 'vehicle_id = ? AND is_archived = ?',
      whereArgs: includeArchived ? [vehicleId] : [vehicleId, 0],
      orderBy: 'is_archived ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(MaintenanceItem.fromMap).toList();
  }

  Future<MaintenanceItem?> findActiveByName(
    String vehicleId,
    String name, {
    String? excludingId,
    sqflite.DatabaseExecutor? executor,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      return null;
    }

    final db = await _executor(executor);
    final rows = await db.query(
      'maintenance_items',
      where: excludingId == null
          ? 'vehicle_id = ? AND is_archived = ? AND name COLLATE NOCASE = ?'
          : 'vehicle_id = ? AND is_archived = ? AND name COLLATE NOCASE = ? AND id != ?',
      whereArgs: excludingId == null
          ? [vehicleId, 0, cleanName]
          : [vehicleId, 0, cleanName, excludingId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return MaintenanceItem.fromMap(rows.first);
  }

  Future<void> archive(
    String id,
    DateTime updatedAt, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.update(
      'maintenance_items',
      {'is_archived': 1, 'updated_at': updatedAt.toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> restore(
    String id,
    DateTime updatedAt, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.update(
      'maintenance_items',
      {'is_archived': 0, 'updated_at': updatedAt.toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<sqflite.DatabaseExecutor> _executor(
    sqflite.DatabaseExecutor? executor,
  ) async {
    return executor ?? await _database.database;
  }
}
