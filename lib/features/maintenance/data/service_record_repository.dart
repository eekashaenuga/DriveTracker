import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/database/app_database.dart';
import '../domain/service_record.dart';

class ServiceRecordRepository {
  ServiceRecordRepository(this._database);

  final AppDatabase _database;

  Future<void> insertRecord(
    ServiceRecord record, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.insert('services', record.toMap());
  }

  Future<void> updateRecord(
    ServiceRecord record, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.update(
      'services',
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  Future<void> deleteRecord(
    String id, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.delete('services', where: 'id = ?', whereArgs: [id]);
  }

  Future<ServiceRecord?> getById(
    String id, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'services',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return ServiceRecord.fromMap(rows.first);
  }

  Future<ServiceRecordWithItems?> getWithItems(
    String id, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final record = await getById(id, executor: db);
    if (record == null) {
      return null;
    }
    final items = await listItemsForService(id, executor: db);
    return ServiceRecordWithItems(record: record, items: items);
  }

  Future<List<ServiceRecord>> listForVehicle(
    String vehicleId, {
    int? limit,
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'services',
      where: 'vehicle_id = ?',
      whereArgs: [vehicleId],
      orderBy: 'event_datetime DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(ServiceRecord.fromMap).toList();
  }

  Future<void> insertItem(
    ServiceItem item, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.insert('service_items', item.toMap());
  }

  Future<void> replaceItemsForService(
    String serviceId,
    List<ServiceItem> items, {
    required sqflite.DatabaseExecutor executor,
  }) async {
    await executor.delete(
      'service_items',
      where: 'service_id = ?',
      whereArgs: [serviceId],
    );
    for (final item in items) {
      await executor.insert('service_items', item.toMap());
    }
  }

  Future<List<ServiceItem>> listItemsForService(
    String serviceId, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'service_items',
      where: 'service_id = ?',
      whereArgs: [serviceId],
      orderBy: 'created_at ASC',
    );
    return rows.map(ServiceItem.fromMap).toList();
  }

  Future<List<MaintenanceCompletion>> completionsForMaintenanceItem(
    String vehicleId,
    String maintenanceItemId, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.rawQuery(
      '''
      SELECT
        s.id AS service_id,
        s.event_datetime,
        s.odometer,
        s.total_cost_minor,
        s.garage,
        s.created_at AS service_created_at,
        s.is_baseline,
        si.id AS service_item_id,
        si.maintenance_item_id,
        si.item_name,
        si.notes AS item_notes
      FROM service_items si
      JOIN services s ON s.id = si.service_id
      WHERE s.vehicle_id = ?
        AND si.maintenance_item_id = ?
      ORDER BY s.event_datetime DESC, s.created_at DESC
      ''',
      [vehicleId, maintenanceItemId],
    );
    return [
      for (final row in rows)
        MaintenanceCompletion(
          serviceId: row['service_id'] as String,
          serviceItemId: row['service_item_id'] as String,
          maintenanceItemId: row['maintenance_item_id'] as String,
          itemName: row['item_name'] as String,
          eventDateTime: DateTime.parse(row['event_datetime'] as String),
          createdAt: DateTime.parse(row['service_created_at'] as String),
          odometer: row['odometer'] as int?,
          totalCostMinor: row['total_cost_minor'] as int,
          garage: row['garage'] as String?,
          notes: row['item_notes'] as String?,
          isBaseline: row['is_baseline'] == 1,
        ),
    ];
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
      FROM services
      WHERE vehicle_id = ?
        AND is_baseline = 0
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
