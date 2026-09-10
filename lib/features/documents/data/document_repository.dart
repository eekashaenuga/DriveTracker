import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/database/app_database.dart';
import '../domain/vehicle_document.dart';

class DocumentRepository {
  DocumentRepository(this._database);

  final AppDatabase _database;

  Future<void> insert(
    VehicleDocument document, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.insert('documents', document.toMap());
  }

  Future<void> update(
    VehicleDocument document, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.update(
      'documents',
      document.toMap(),
      where: 'id = ?',
      whereArgs: [document.id],
    );
  }

  Future<void> delete(
    String documentId, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.delete('documents', where: 'id = ?', whereArgs: [documentId]);
  }

  Future<VehicleDocument?> getById(
    String documentId, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'documents',
      where: 'id = ?',
      whereArgs: [documentId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return VehicleDocument.fromMap(rows.first);
  }

  Future<List<VehicleDocument>> listForVehicle(
    String vehicleId, {
    bool includeArchived = false,
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'documents',
      where: includeArchived
          ? 'vehicle_id = ?'
          : 'vehicle_id = ? AND is_archived = 0',
      whereArgs: [vehicleId],
      orderBy: 'is_archived ASC, expiry_date IS NULL ASC, expiry_date ASC, updated_at DESC',
    );
    return rows.map(VehicleDocument.fromMap).toList();
  }

  Future<List<VehicleDocument>> activeExpiringForVehicle(
    String vehicleId, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'documents',
      where: 'vehicle_id = ? AND is_archived = 0 AND expiry_date IS NOT NULL',
      whereArgs: [vehicleId],
      orderBy: 'expiry_date ASC, title COLLATE NOCASE ASC',
    );
    return rows.map(VehicleDocument.fromMap).toList();
  }

  Future<sqflite.DatabaseExecutor> _executor(
    sqflite.DatabaseExecutor? executor,
  ) async {
    return executor ?? await _database.database;
  }
}
