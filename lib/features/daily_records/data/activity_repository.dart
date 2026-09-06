import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/database/app_database.dart';
import '../domain/daily_activity.dart';

class ActivityRepository {
  ActivityRepository(this._database);

  final AppDatabase _database;

  Future<List<DailyActivity>> listForVehicle(
    String vehicleId, {
    DailyActivityType type = DailyActivityType.all,
    int limit = 50,
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final activities = <DailyActivity>[];

    if (type == DailyActivityType.all || type == DailyActivityType.refuel) {
      activities.addAll(await _refuels(db, vehicleId, limit));
    }
    if (type == DailyActivityType.all || type == DailyActivityType.expense) {
      activities.addAll(await _expenses(db, vehicleId, limit));
    }
    if (type == DailyActivityType.all || type == DailyActivityType.income) {
      activities.addAll(await _income(db, vehicleId, limit));
    }
    if (type == DailyActivityType.all || type == DailyActivityType.service) {
      activities.addAll(await _services(db, vehicleId, limit));
    }
    if (type == DailyActivityType.all || type == DailyActivityType.odometer) {
      activities.addAll(await _manualOdometers(db, vehicleId, limit));
    }

    activities.sort((a, b) {
      final eventCompare = b.eventDateTime.compareTo(a.eventDateTime);
      if (eventCompare != 0) {
        return eventCompare;
      }
      return b.createdAt.compareTo(a.createdAt);
    });
    return activities.take(limit).toList();
  }

  Future<List<DailyActivity>> _refuels(
    sqflite.DatabaseExecutor db,
    String vehicleId,
    int limit,
  ) async {
    final rows = await db.query(
      'refuels',
      where: 'vehicle_id = ?',
      whereArgs: [vehicleId],
      orderBy: 'event_datetime DESC, created_at DESC',
      limit: limit,
    );
    return [
      for (final row in rows)
        DailyActivity(
          type: DailyActivityType.refuel,
          recordId: row['id'] as String,
          vehicleId: row['vehicle_id'] as String,
          eventDateTime: DateTime.parse(row['event_datetime'] as String),
          createdAt: DateTime.parse(row['created_at'] as String),
          title: 'Refuel',
          subtitle: _join([
            row['station'] as String?,
            (row['is_full_tank'] == 1) ? 'Full tank' : 'Partial fill',
          ]),
          amountMinor: row['total_cost_minor'] as int,
          odometer: row['odometer'] as int,
        ),
    ];
  }

  Future<List<DailyActivity>> _expenses(
    sqflite.DatabaseExecutor db,
    String vehicleId,
    int limit,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT e.*, c.name AS category_name
      FROM expenses e
      JOIN record_categories c ON c.id = e.category_id
      WHERE e.vehicle_id = ?
      ORDER BY e.event_datetime DESC, e.created_at DESC
      LIMIT ?
      ''',
      [vehicleId, limit],
    );
    return [
      for (final row in rows)
        DailyActivity(
          type: DailyActivityType.expense,
          recordId: row['id'] as String,
          vehicleId: row['vehicle_id'] as String,
          eventDateTime: DateTime.parse(row['event_datetime'] as String),
          createdAt: DateTime.parse(row['created_at'] as String),
          title: row['category_name'] as String,
          subtitle: _join([row['merchant'] as String?, 'Expense']),
          amountMinor: row['amount_minor'] as int,
          odometer: row['odometer'] as int?,
        ),
    ];
  }

  Future<List<DailyActivity>> _income(
    sqflite.DatabaseExecutor db,
    String vehicleId,
    int limit,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT i.*, c.name AS category_name
      FROM income_records i
      JOIN record_categories c ON c.id = i.category_id
      WHERE i.vehicle_id = ?
      ORDER BY i.event_datetime DESC, i.created_at DESC
      LIMIT ?
      ''',
      [vehicleId, limit],
    );
    return [
      for (final row in rows)
        DailyActivity(
          type: DailyActivityType.income,
          recordId: row['id'] as String,
          vehicleId: row['vehicle_id'] as String,
          eventDateTime: DateTime.parse(row['event_datetime'] as String),
          createdAt: DateTime.parse(row['created_at'] as String),
          title: row['category_name'] as String,
          subtitle: _join([row['source'] as String?, 'Income']),
          amountMinor: row['amount_minor'] as int,
          odometer: row['odometer'] as int?,
        ),
    ];
  }

  Future<List<DailyActivity>> _manualOdometers(
    sqflite.DatabaseExecutor db,
    String vehicleId,
    int limit,
  ) async {
    final rows = await db.query(
      'odometer_entries',
      where: 'vehicle_id = ? AND source_type = ?',
      whereArgs: [vehicleId, 'MANUAL'],
      orderBy: 'event_datetime DESC, created_at DESC',
      limit: limit,
    );
    return [
      for (final row in rows)
        DailyActivity(
          type: DailyActivityType.odometer,
          recordId: row['id'] as String,
          vehicleId: row['vehicle_id'] as String,
          eventDateTime: DateTime.parse(row['event_datetime'] as String),
          createdAt: DateTime.parse(row['created_at'] as String),
          title: 'Odometer',
          subtitle: 'Manual reading',
          odometer: row['odometer'] as int,
        ),
    ];
  }

  Future<List<DailyActivity>> _services(
    sqflite.DatabaseExecutor db,
    String vehicleId,
    int limit,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        s.*,
        (
          SELECT si.item_name
          FROM service_items si
          WHERE si.service_id = s.id
          ORDER BY si.created_at ASC
          LIMIT 1
        ) AS first_item_name,
        (
          SELECT COUNT(*)
          FROM service_items si
          WHERE si.service_id = s.id
        ) AS item_count
      FROM services s
      WHERE s.vehicle_id = ?
      ORDER BY s.event_datetime DESC, s.created_at DESC
      LIMIT ?
      ''',
      [vehicleId, limit],
    );
    return [
      for (final row in rows)
        DailyActivity(
          type: DailyActivityType.service,
          recordId: row['id'] as String,
          vehicleId: row['vehicle_id'] as String,
          eventDateTime: DateTime.parse(row['event_datetime'] as String),
          createdAt: DateTime.parse(row['created_at'] as String),
          title: row['is_baseline'] == 1 ? 'Maintenance baseline' : 'Service',
          subtitle: _join([
            row['garage'] as String?,
            _serviceItemSummary(
              row['first_item_name'] as String?,
              row['item_count'] as int,
            ),
          ]),
          amountMinor: row['is_baseline'] == 1
              ? null
              : row['total_cost_minor'] as int,
          odometer: row['odometer'] as int?,
        ),
    ];
  }

  String _join(List<String?> values) {
    return values
        .where((value) => value != null && value.trim().isNotEmpty)
        .map((value) => value!.trim())
        .join(' / ');
  }

  String? _serviceItemSummary(String? firstItemName, int itemCount) {
    if (firstItemName == null || firstItemName.trim().isEmpty) {
      return null;
    }
    if (itemCount <= 1) {
      return firstItemName;
    }
    return '$firstItemName + ${itemCount - 1} more';
  }

  Future<sqflite.DatabaseExecutor> _executor(
    sqflite.DatabaseExecutor? executor,
  ) async {
    return executor ?? await _database.database;
  }
}
