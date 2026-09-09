import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/calculations/analytics_date_range.dart';
import '../../../core/database/app_database.dart';
import '../domain/daily_activity.dart';
import '../domain/history_filter.dart';
import '../../vehicles/domain/vehicle.dart';

class ActivityRepository {
  ActivityRepository(this._database);

  final AppDatabase _database;

  Future<List<DailyActivity>> listForVehicle(
    String vehicleId, {
    DailyActivityType type = DailyActivityType.all,
    int limit = 50,
    sqflite.DatabaseExecutor? executor,
  }) {
    return search(
      HistoryFilter(vehicleId: vehicleId, type: type),
      limit: limit,
      executor: executor,
    );
  }

  Future<List<DailyActivity>> search(
    HistoryFilter filter, {
    int limit = 200,
    DateTime? now,
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final range = filter.range.resolve(now ?? DateTime.now());
    final activities = <DailyActivity>[];

    if (_includes(filter.type, DailyActivityType.refuel) &&
        filter.categoryId == null) {
      activities.addAll(await _refuels(db, filter, range, limit));
    }
    if (_includes(filter.type, DailyActivityType.expense)) {
      activities.addAll(await _expenses(db, filter, range, limit));
    }
    if (_includes(filter.type, DailyActivityType.income)) {
      activities.addAll(await _income(db, filter, range, limit));
    }
    if (_includes(filter.type, DailyActivityType.service) &&
        filter.categoryId == null) {
      activities.addAll(await _services(db, filter, range, limit));
    }
    if (_includes(filter.type, DailyActivityType.odometer) &&
        filter.categoryId == null) {
      activities.addAll(await _manualOdometers(db, filter, range, limit));
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
    HistoryFilter filter,
    ResolvedAnalyticsRange range,
    int limit,
  ) async {
    final query = _activityQuery(
      alias: 'r',
      filter: filter,
      range: range,
      searchColumns: const [
        'r.station',
        'r.notes',
        'r.fuel_type',
        'v.name',
        'v.make',
        'v.model',
        'v.registration',
      ],
    );
    final rows = await db.rawQuery(
      '''
      SELECT r.*, v.name AS vehicle_name, v.make, v.model, v.distance_unit
      FROM refuels r
      JOIN vehicles v ON v.id = r.vehicle_id
      ${query.whereClause}
      ORDER BY r.event_datetime DESC, r.created_at DESC
      LIMIT ?
      ''',
      [...query.args, limit],
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
          vehicleName: row['vehicle_name'] as String,
          vehicleDescription: _vehicleDescription(row),
          vehicleDistanceUnit: DistanceUnit.fromStorage(
            row['distance_unit'] as String,
          ),
        ),
    ];
  }

  Future<List<DailyActivity>> _expenses(
    sqflite.DatabaseExecutor db,
    HistoryFilter filter,
    ResolvedAnalyticsRange range,
    int limit,
  ) async {
    final query = _activityQuery(
      alias: 'e',
      filter: filter,
      range: range,
      categoryColumn: 'e.category_id',
      searchColumns: const [
        'e.merchant',
        'e.payment_method',
        'e.notes',
        'c.name',
        'v.name',
        'v.make',
        'v.model',
        'v.registration',
      ],
    );
    final rows = await db.rawQuery(
      '''
      SELECT e.*, c.name AS category_name, v.name AS vehicle_name, v.make, v.model, v.distance_unit
      FROM expenses e
      JOIN record_categories c ON c.id = e.category_id
      JOIN vehicles v ON v.id = e.vehicle_id
      ${query.whereClause}
      ORDER BY e.event_datetime DESC, e.created_at DESC
      LIMIT ?
      ''',
      [...query.args, limit],
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
          vehicleName: row['vehicle_name'] as String,
          vehicleDescription: _vehicleDescription(row),
          vehicleDistanceUnit: DistanceUnit.fromStorage(
            row['distance_unit'] as String,
          ),
          categoryId: row['category_id'] as String,
          categoryName: row['category_name'] as String,
        ),
    ];
  }

  Future<List<DailyActivity>> _income(
    sqflite.DatabaseExecutor db,
    HistoryFilter filter,
    ResolvedAnalyticsRange range,
    int limit,
  ) async {
    final query = _activityQuery(
      alias: 'i',
      filter: filter,
      range: range,
      categoryColumn: 'i.category_id',
      searchColumns: const [
        'i.source',
        'i.notes',
        'c.name',
        'v.name',
        'v.make',
        'v.model',
        'v.registration',
      ],
    );
    final rows = await db.rawQuery(
      '''
      SELECT i.*, c.name AS category_name, v.name AS vehicle_name, v.make, v.model, v.distance_unit
      FROM income_records i
      JOIN record_categories c ON c.id = i.category_id
      JOIN vehicles v ON v.id = i.vehicle_id
      ${query.whereClause}
      ORDER BY i.event_datetime DESC, i.created_at DESC
      LIMIT ?
      ''',
      [...query.args, limit],
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
          vehicleName: row['vehicle_name'] as String,
          vehicleDescription: _vehicleDescription(row),
          vehicleDistanceUnit: DistanceUnit.fromStorage(
            row['distance_unit'] as String,
          ),
          categoryId: row['category_id'] as String,
          categoryName: row['category_name'] as String,
        ),
    ];
  }

  Future<List<DailyActivity>> _manualOdometers(
    sqflite.DatabaseExecutor db,
    HistoryFilter filter,
    ResolvedAnalyticsRange range,
    int limit,
  ) async {
    final query = _activityQuery(
      alias: 'o',
      filter: filter,
      range: range,
      searchColumns: const [
        'CAST(o.odometer AS TEXT)',
        'v.name',
        'v.make',
        'v.model',
        'v.registration',
      ],
    );
    final rows = await db.rawQuery(
      '''
      SELECT o.*, v.name AS vehicle_name, v.make, v.model, v.distance_unit
      FROM odometer_entries o
      JOIN vehicles v ON v.id = o.vehicle_id
      ${query.whereClause}
        AND o.source_type = ?
      ORDER BY o.event_datetime DESC, o.created_at DESC
      LIMIT ?
      ''',
      [...query.args, 'MANUAL', limit],
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
          vehicleName: row['vehicle_name'] as String,
          vehicleDescription: _vehicleDescription(row),
          vehicleDistanceUnit: DistanceUnit.fromStorage(
            row['distance_unit'] as String,
          ),
        ),
    ];
  }

  Future<List<DailyActivity>> _services(
    sqflite.DatabaseExecutor db,
    HistoryFilter filter,
    ResolvedAnalyticsRange range,
    int limit,
  ) async {
    final query = _activityQuery(
      alias: 's',
      filter: filter,
      range: range,
      searchColumns: const [
        's.garage',
        's.notes',
        'v.name',
        'v.make',
        'v.model',
        'v.registration',
      ],
      extraSearchSql: '''
          EXISTS (
            SELECT 1
            FROM service_items search_items
            WHERE search_items.service_id = s.id
              AND (
                search_items.item_name LIKE ? COLLATE NOCASE
                OR COALESCE(search_items.notes, '') LIKE ? COLLATE NOCASE
              )
          )
          ''',
      extraSearchArgCount: 2,
    );
    final rows = await db.rawQuery(
      '''
      SELECT
        s.*,
        v.name AS vehicle_name,
        v.make,
        v.model,
        v.distance_unit,
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
      JOIN vehicles v ON v.id = s.vehicle_id
      ${query.whereClause}
      ORDER BY s.event_datetime DESC, s.created_at DESC
      LIMIT ?
      ''',
      [...query.args, limit],
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
          vehicleName: row['vehicle_name'] as String,
          vehicleDescription: _vehicleDescription(row),
          vehicleDistanceUnit: DistanceUnit.fromStorage(
            row['distance_unit'] as String,
          ),
        ),
    ];
  }

  _ActivityQuery _activityQuery({
    required String alias,
    required HistoryFilter filter,
    required ResolvedAnalyticsRange range,
    String? categoryColumn,
    List<String> searchColumns = const [],
    String? extraSearchSql,
    int extraSearchArgCount = 0,
  }) {
    final conditions = <String>[];
    final args = <Object?>[];

    final vehicleId = filter.vehicleId;
    if (vehicleId != null) {
      conditions.add('$alias.vehicle_id = ?');
      args.add(vehicleId);
    }
    final start = range.startInclusive;
    if (start != null) {
      conditions.add('$alias.event_datetime >= ?');
      args.add(start.toUtc().toIso8601String());
    }
    final end = range.endExclusive;
    if (end != null) {
      conditions.add('$alias.event_datetime < ?');
      args.add(end.toUtc().toIso8601String());
    }
    final categoryId = filter.categoryId;
    if (categoryId != null) {
      if (categoryColumn == null) {
        conditions.add('1 = 0');
      } else {
        conditions.add('$categoryColumn = ?');
        args.add(categoryId);
      }
    }

    final search = filter.searchQuery.trim();
    if (search.isNotEmpty) {
      final like = '%$search%';
      final searchConditions = <String>[
        for (final column in searchColumns)
          'COALESCE($column, \'\') LIKE ? COLLATE NOCASE',
      ];
      args.addAll(List<Object?>.filled(searchColumns.length, like));
      if (extraSearchSql != null) {
        searchConditions.add(extraSearchSql);
        args.addAll(List<Object?>.filled(extraSearchArgCount, like));
      }
      conditions.add('(${searchConditions.join(' OR ')})');
    }

    final whereClause = conditions.isEmpty
        ? 'WHERE 1 = 1'
        : 'WHERE ${conditions.join(' AND ')}';
    return _ActivityQuery(whereClause: whereClause, args: args);
  }

  bool _includes(DailyActivityType selected, DailyActivityType candidate) {
    return selected == DailyActivityType.all || selected == candidate;
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

  String _vehicleDescription(Map<String, Object?> row) {
    return _join([row['make'] as String?, row['model'] as String?]);
  }

  Future<sqflite.DatabaseExecutor> _executor(
    sqflite.DatabaseExecutor? executor,
  ) async {
    return executor ?? await _database.database;
  }
}

class _ActivityQuery {
  const _ActivityQuery({required this.whereClause, required this.args});

  final String whereClause;
  final List<Object?> args;
}
