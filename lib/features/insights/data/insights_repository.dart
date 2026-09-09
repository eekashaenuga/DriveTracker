import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/calculations/analytics_date_range.dart';
import '../../../core/database/app_database.dart';
import '../../../core/utilities/money.dart';
import '../../daily_records/domain/daily_activity.dart';
import '../../daily_records/domain/fuel_economy_calculator.dart';
import '../../daily_records/domain/refuel.dart';
import '../../odometer/domain/odometer_entry.dart';
import '../../vehicles/domain/vehicle.dart';
import '../domain/vehicle_insights.dart';

class InsightsRepository {
  InsightsRepository(this._database);

  final AppDatabase _database;

  Future<VehicleInsights> loadInsights({
    required String? vehicleId,
    required AnalyticsDateRange range,
    DateTime? now,
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final scope = await _scope(db, vehicleId);
    final selectedVehicle = scope.vehicle;
    final vehicleIds = scope.isAllVehicles
        ? (await _activeVehicles(db)).map((vehicle) => vehicle.id).toList()
        : selectedVehicle == null
        ? const <String>[]
        : [selectedVehicle.id];
    final resolvedRange = range.resolve(now ?? DateTime.now());

    final refuels = await _refuels(
      db,
      vehicleIds: vehicleIds,
      range: resolvedRange,
    );
    final expenses = await _expenses(
      db,
      vehicleIds: vehicleIds,
      range: resolvedRange,
    );
    final income = await _income(
      db,
      vehicleIds: vehicleIds,
      range: resolvedRange,
    );
    final services = await _services(
      db,
      vehicleIds: vehicleIds,
      range: resolvedRange,
    );
    final odometers = scope.isAllVehicles || selectedVehicle == null
        ? const <OdometerEntry>[]
        : await _odometers(db, vehicleId: selectedVehicle.id);
    final allRefuelsForEconomy = scope.isAllVehicles || selectedVehicle == null
        ? const <Refuel>[]
        : await _refuelsForEconomy(db, vehicleId: selectedVehicle.id);

    final distance = _distance(scope, odometers, resolvedRange);
    final averageFuelEconomy = _fuelEconomy(
      scope,
      allRefuelsForEconomy,
      resolvedRange,
    );
    final fuelSpend = _sum(refuels.map((record) => record.totalCostMinor));
    final serviceSpend = _sum(services.map((record) => record.totalCostMinor));
    final expenseSpend = _sum(expenses.map((record) => record.amountMinor));
    final incomeTotal = _sum(income.map((record) => record.amountMinor));
    final runningExpenseSpend = _sum(
      expenses
          .where((record) => _isRunningExpenseCategory(record.categoryId))
          .map((record) => record.amountMinor),
    );

    final events = <DateTime>[
      ...refuels.map((record) => record.eventDateTime),
      ...expenses.map((record) => record.eventDateTime),
      ...services.map((record) => record.eventDateTime),
      ...income.map((record) => record.eventDateTime),
    ]..sort();
    final buckets = _amountBuckets(
      range: resolvedRange,
      earliestEvent: events.isEmpty ? null : events.first,
      latestEvent: events.isEmpty ? null : events.last,
      refuels: refuels,
      expenses: expenses,
      services: services,
      income: income,
    );

    return VehicleInsights(
      scope: scope,
      range: resolvedRange,
      fuelSpendMinor: fuelSpend,
      serviceSpendMinor: serviceSpend,
      expenseSpendMinor: expenseSpend,
      runningSpendMinor: fuelSpend + serviceSpend + runningExpenseSpend,
      incomeMinor: incomeTotal,
      distance: distance,
      averageFuelEconomy: averageFuelEconomy,
      averageFuelPriceMicrosPerLitre: _weightedFuelPrice(refuels),
      spendingBuckets: buckets,
      breakdown: _breakdown(
        fuelSpend: fuelSpend,
        serviceSpend: serviceSpend,
        expenses: expenses,
      ),
      fuelEconomyTrend: _fuelEconomyTrend(
        scope,
        allRefuelsForEconomy,
        resolvedRange,
      ),
      fuelPriceTrend: _fuelPriceTrend(buckets, refuels),
      odometerTrend: _odometerTrend(scope, odometers, resolvedRange),
    );
  }

  Future<InsightScope> _scope(
    sqflite.DatabaseExecutor db,
    String? vehicleId,
  ) async {
    if (vehicleId == null) {
      return const InsightScope.allVehicles();
    }
    final rows = await db.query(
      'vehicles',
      where: 'id = ?',
      whereArgs: [vehicleId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const InsightScope.allVehicles();
    }
    return InsightScope.vehicle(Vehicle.fromMap(rows.first));
  }

  Future<List<Vehicle>> _activeVehicles(sqflite.DatabaseExecutor db) async {
    final rows = await db.query(
      'vehicles',
      where: 'is_archived = ?',
      whereArgs: [0],
      orderBy: 'created_at DESC',
    );
    return rows.map(Vehicle.fromMap).toList();
  }

  Future<List<_RefuelRecord>> _refuels(
    sqflite.DatabaseExecutor db, {
    required List<String> vehicleIds,
    required ResolvedAnalyticsRange range,
  }) async {
    if (vehicleIds.isEmpty) {
      return const [];
    }
    final query = _recordQuery('r', vehicleIds, range);
    final rows = await db.rawQuery('''
      SELECT r.*
      FROM refuels r
      ${query.whereClause}
      ORDER BY r.event_datetime ASC, r.created_at ASC
      ''', query.args);
    return rows.map(_RefuelRecord.fromMap).toList();
  }

  Future<List<Refuel>> _refuelsForEconomy(
    sqflite.DatabaseExecutor db, {
    required String vehicleId,
  }) async {
    final rows = await db.query(
      'refuels',
      where: 'vehicle_id = ?',
      whereArgs: [vehicleId],
      orderBy: 'event_datetime ASC, created_at ASC',
    );
    return rows.map(Refuel.fromMap).toList();
  }

  Future<List<_ExpenseRecord>> _expenses(
    sqflite.DatabaseExecutor db, {
    required List<String> vehicleIds,
    required ResolvedAnalyticsRange range,
  }) async {
    if (vehicleIds.isEmpty) {
      return const [];
    }
    final query = _recordQuery('e', vehicleIds, range);
    final rows = await db.rawQuery('''
      SELECT e.*, c.name AS category_name
      FROM expenses e
      JOIN record_categories c ON c.id = e.category_id
      ${query.whereClause}
      ORDER BY e.event_datetime ASC, e.created_at ASC
      ''', query.args);
    return rows.map(_ExpenseRecord.fromMap).toList();
  }

  Future<List<_IncomeRecord>> _income(
    sqflite.DatabaseExecutor db, {
    required List<String> vehicleIds,
    required ResolvedAnalyticsRange range,
  }) async {
    if (vehicleIds.isEmpty) {
      return const [];
    }
    final query = _recordQuery('i', vehicleIds, range);
    final rows = await db.rawQuery('''
      SELECT i.*, c.name AS category_name
      FROM income_records i
      JOIN record_categories c ON c.id = i.category_id
      ${query.whereClause}
      ORDER BY i.event_datetime ASC, i.created_at ASC
      ''', query.args);
    return rows.map(_IncomeRecord.fromMap).toList();
  }

  Future<List<_ServiceSpendRecord>> _services(
    sqflite.DatabaseExecutor db, {
    required List<String> vehicleIds,
    required ResolvedAnalyticsRange range,
  }) async {
    if (vehicleIds.isEmpty) {
      return const [];
    }
    final query = _recordQuery('s', vehicleIds, range);
    final rows = await db.rawQuery('''
      SELECT s.*
      FROM services s
      ${query.whereClause}
        AND s.is_baseline = 0
      ORDER BY s.event_datetime ASC, s.created_at ASC
      ''', query.args);
    return rows.map(_ServiceSpendRecord.fromMap).toList();
  }

  Future<List<OdometerEntry>> _odometers(
    sqflite.DatabaseExecutor db, {
    required String vehicleId,
  }) async {
    final rows = await db.query(
      'odometer_entries',
      where: 'vehicle_id = ?',
      whereArgs: [vehicleId],
      orderBy: 'event_datetime ASC, created_at ASC',
    );
    return rows.map(OdometerEntry.fromMap).toList();
  }

  _SqlQuery _recordQuery(
    String alias,
    List<String> vehicleIds,
    ResolvedAnalyticsRange range,
  ) {
    final conditions = <String>[];
    final args = <Object?>[];
    if (vehicleIds.length == 1) {
      conditions.add('$alias.vehicle_id = ?');
      args.add(vehicleIds.single);
    } else {
      final placeholders = List.filled(vehicleIds.length, '?').join(', ');
      conditions.add('$alias.vehicle_id IN ($placeholders)');
      args.addAll(vehicleIds);
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
    return _SqlQuery(
      whereClause: 'WHERE ${conditions.join(' AND ')}',
      args: args,
    );
  }

  DistanceInsight _distance(
    InsightScope scope,
    List<OdometerEntry> odometers,
    ResolvedAnalyticsRange range,
  ) {
    final unit = scope.distanceUnit;
    if (scope.isAllVehicles) {
      return const DistanceInsight.unavailable(
        'Select one vehicle for distance-based metrics.',
      );
    }
    if (unit == null) {
      return const DistanceInsight.unavailable('Distance unit unavailable.');
    }
    final valid = _chronologicalValidOdometers(odometers);
    if (valid.length < 2) {
      return const DistanceInsight.unavailable(
        'At least two valid odometer readings are needed.',
      );
    }

    final start = _startOdometer(valid, range);
    final end = _endOdometer(valid, range);
    if (start == null || end == null || identical(start, end)) {
      return const DistanceInsight.unavailable(
        'At least two valid odometer readings are needed in this range.',
      );
    }
    if (end.eventDateTime.toLocal().isBefore(start.eventDateTime.toLocal())) {
      return const DistanceInsight.unavailable(
        'Odometer readings are not chronological for this range.',
      );
    }
    final distance = end.odometer - start.odometer;
    if (distance < 0) {
      return const DistanceInsight.unavailable(
        'Odometer readings cannot produce a valid distance.',
      );
    }
    return DistanceInsight.available(distance, unit);
  }

  List<OdometerEntry> _chronologicalValidOdometers(
    List<OdometerEntry> odometers,
  ) {
    final sorted = [...odometers]
      ..sort((a, b) {
        final eventCompare = a.eventDateTime.compareTo(b.eventDateTime);
        if (eventCompare != 0) {
          return eventCompare;
        }
        return a.createdAt.compareTo(b.createdAt);
      });
    final valid = <OdometerEntry>[];
    var highest = -1;
    for (final entry in sorted) {
      if (entry.odometer < highest) {
        continue;
      }
      valid.add(entry);
      highest = entry.odometer;
    }
    return valid;
  }

  OdometerEntry? _startOdometer(
    List<OdometerEntry> valid,
    ResolvedAnalyticsRange range,
  ) {
    final start = range.startInclusive;
    if (start == null) {
      return valid.first;
    }
    for (final entry in valid.reversed) {
      if (!entry.eventDateTime.toLocal().isAfter(start)) {
        return entry;
      }
    }
    for (final entry in valid) {
      if (range.contains(entry.eventDateTime)) {
        return entry;
      }
    }
    return null;
  }

  OdometerEntry? _endOdometer(
    List<OdometerEntry> valid,
    ResolvedAnalyticsRange range,
  ) {
    final end = range.endExclusive;
    if (end == null) {
      return valid.last;
    }
    for (final entry in valid.reversed) {
      if (entry.eventDateTime.toLocal().isBefore(end)) {
        return entry;
      }
    }
    return null;
  }

  FuelEconomyInsight _fuelEconomy(
    InsightScope scope,
    List<Refuel> refuels,
    ResolvedAnalyticsRange range,
  ) {
    if (scope.isAllVehicles) {
      return const FuelEconomyInsight.unavailable(
        'Select one vehicle for fuel economy.',
      );
    }
    final unit = scope.distanceUnit;
    if (unit != DistanceUnit.miles) {
      return const FuelEconomyInsight.unavailable(
        'UK MPG needs mile-based odometer readings.',
      );
    }
    final intervals = FuelEconomyCalculator.validIntervals(
      refuels: refuels,
      distanceUnit: DistanceUnit.miles,
    ).where((interval) => range.contains(interval.endRefuel.eventDateTime));
    final distance = _sum(intervals.map((interval) => interval.distance));
    final volume = _sum(
      intervals.map((interval) => interval.volumeMillilitres),
    );
    final ukMpg = _ukMpg(distance: distance, volumeMillilitres: volume);
    if (ukMpg == null) {
      return const FuelEconomyInsight.unavailable(
        'Add valid full-to-full refuels to calculate MPG.',
      );
    }
    return FuelEconomyInsight.available(
      ukMpg: ukMpg,
      distance: distance,
      volumeMillilitres: volume,
    );
  }

  List<InsightAmountBucket> _amountBuckets({
    required ResolvedAnalyticsRange range,
    required DateTime? earliestEvent,
    required DateTime? latestEvent,
    required List<_RefuelRecord> refuels,
    required List<_ExpenseRecord> expenses,
    required List<_ServiceSpendRecord> services,
    required List<_IncomeRecord> income,
  }) {
    final buckets = range.buckets(
      earliestEvent: earliestEvent,
      latestEvent: latestEvent,
    );
    return [
      for (var index = 0; index < buckets.length; index += 1)
        InsightAmountBucket(
          index: index,
          startInclusive: buckets[index].startInclusive,
          endExclusive: buckets[index].endExclusive,
          label: buckets[index].label,
          fuelSpendMinor: _sum(
            refuels
                .where(
                  (record) => buckets[index].contains(record.eventDateTime),
                )
                .map((record) => record.totalCostMinor),
          ),
          serviceSpendMinor: _sum(
            services
                .where(
                  (record) => buckets[index].contains(record.eventDateTime),
                )
                .map((record) => record.totalCostMinor),
          ),
          expenseSpendMinor: _sum(
            expenses
                .where(
                  (record) => buckets[index].contains(record.eventDateTime),
                )
                .map((record) => record.amountMinor),
          ),
          incomeMinor: _sum(
            income
                .where(
                  (record) => buckets[index].contains(record.eventDateTime),
                )
                .map((record) => record.amountMinor),
          ),
        ),
    ];
  }

  List<InsightBreakdownItem> _breakdown({
    required int fuelSpend,
    required int serviceSpend,
    required List<_ExpenseRecord> expenses,
  }) {
    final items = <InsightBreakdownItem>[
      if (fuelSpend > 0)
        InsightBreakdownItem(
          key: 'fuel',
          label: 'Fuel',
          amountMinor: fuelSpend,
          type: DailyActivityType.refuel,
        ),
      if (serviceSpend > 0)
        InsightBreakdownItem(
          key: 'service',
          label: 'Service',
          amountMinor: serviceSpend,
          type: DailyActivityType.service,
        ),
    ];

    final expenseTotals = <String, int>{};
    final expenseNames = <String, String>{};
    for (final expense in expenses) {
      expenseTotals.update(
        expense.categoryId,
        (value) => value + expense.amountMinor,
        ifAbsent: () => expense.amountMinor,
      );
      expenseNames[expense.categoryId] = expense.categoryName;
    }
    for (final entry in expenseTotals.entries) {
      if (entry.value <= 0) {
        continue;
      }
      items.add(
        InsightBreakdownItem(
          key: entry.key,
          label: expenseNames[entry.key] ?? 'Expense',
          amountMinor: entry.value,
          type: DailyActivityType.expense,
          categoryId: entry.key,
        ),
      );
    }
    items.sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    return items;
  }

  List<FuelEconomyPoint> _fuelEconomyTrend(
    InsightScope scope,
    List<Refuel> refuels,
    ResolvedAnalyticsRange range,
  ) {
    if (scope.distanceUnit != DistanceUnit.miles || scope.isAllVehicles) {
      return const [];
    }
    final intervals = FuelEconomyCalculator.validIntervals(
      refuels: refuels,
      distanceUnit: DistanceUnit.miles,
    ).where((interval) => range.contains(interval.endRefuel.eventDateTime));
    return [
      for (final interval in intervals)
        FuelEconomyPoint(
          date: interval.endRefuel.eventDateTime,
          label: _dateLabel(interval.endRefuel.eventDateTime),
          ukMpg: interval.ukMpg,
          distance: interval.distance,
          volumeMillilitres: interval.volumeMillilitres,
        ),
    ];
  }

  List<FuelPricePoint> _fuelPriceTrend(
    List<InsightAmountBucket> buckets,
    List<_RefuelRecord> refuels,
  ) {
    final points = <FuelPricePoint>[];
    for (final bucket in buckets) {
      final bucketRefuels = refuels.where(
        (record) =>
            !record.eventDateTime.toLocal().isBefore(bucket.startInclusive) &&
            record.eventDateTime.toLocal().isBefore(bucket.endExclusive),
      );
      final weighted = _weightedFuelPrice(bucketRefuels);
      if (weighted != null) {
        points.add(
          FuelPricePoint(
            date: bucket.startInclusive,
            label: bucket.label,
            microsPerLitre: weighted,
          ),
        );
      }
    }
    return points;
  }

  List<OdometerTrendPoint> _odometerTrend(
    InsightScope scope,
    List<OdometerEntry> odometers,
    ResolvedAnalyticsRange range,
  ) {
    if (scope.isAllVehicles) {
      return const [];
    }
    final valid = _chronologicalValidOdometers(odometers)
        .where((entry) => range.contains(entry.eventDateTime))
        .toList();
    if (valid.length < 2) {
      return const [];
    }
    return [
      for (final entry in valid)
        OdometerTrendPoint(
          date: entry.eventDateTime,
          label: _dateLabel(entry.eventDateTime),
          odometer: entry.odometer,
        ),
    ];
  }

  int? _weightedFuelPrice(Iterable<_RefuelRecord> refuels) {
    final totalCostMinor = _sum(refuels.map((record) => record.totalCostMinor));
    final totalVolume = _sum(refuels.map((record) => record.volumeMillilitres));
    if (totalCostMinor <= 0 || totalVolume <= 0) {
      return null;
    }
    return (totalCostMinor *
            FuelNumbers.microsPerPence *
            FuelNumbers.millilitresPerLitre /
            totalVolume)
        .round();
  }

  double? _ukMpg({required int distance, required int volumeMillilitres}) {
    if (distance <= 0 || volumeMillilitres <= 0) {
      return null;
    }
    final litres = volumeMillilitres / FuelNumbers.millilitresPerLitre;
    final gallons = litres * FuelNumbers.imperialGallonsPerLitre;
    if (gallons <= 0) {
      return null;
    }
    return distance / gallons;
  }

  bool _isRunningExpenseCategory(String categoryId) {
    const runningCategories = {
      'cat_expense_parking',
      'cat_expense_toll',
      'cat_expense_repair',
      'cat_expense_parts',
      'cat_expense_cleaning',
      'cat_expense_other',
    };
    return runningCategories.contains(categoryId);
  }

  int _sum(Iterable<int> values) {
    return values.fold(0, (total, value) => total + value);
  }

  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    return '${local.day} ${_monthShort(local.month)}';
  }

  String _monthShort(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  Future<sqflite.DatabaseExecutor> _executor(
    sqflite.DatabaseExecutor? executor,
  ) async {
    return executor ?? await _database.database;
  }
}

class _SqlQuery {
  const _SqlQuery({required this.whereClause, required this.args});

  final String whereClause;
  final List<Object?> args;
}

class _RefuelRecord {
  const _RefuelRecord({
    required this.eventDateTime,
    required this.totalCostMinor,
    required this.volumeMillilitres,
  });

  final DateTime eventDateTime;
  final int totalCostMinor;
  final int volumeMillilitres;

  factory _RefuelRecord.fromMap(Map<String, Object?> map) {
    return _RefuelRecord(
      eventDateTime: DateTime.parse(map['event_datetime'] as String),
      totalCostMinor: map['total_cost_minor'] as int,
      volumeMillilitres: map['volume_millilitres'] as int,
    );
  }
}

class _ExpenseRecord {
  const _ExpenseRecord({
    required this.eventDateTime,
    required this.categoryId,
    required this.categoryName,
    required this.amountMinor,
  });

  final DateTime eventDateTime;
  final String categoryId;
  final String categoryName;
  final int amountMinor;

  factory _ExpenseRecord.fromMap(Map<String, Object?> map) {
    return _ExpenseRecord(
      eventDateTime: DateTime.parse(map['event_datetime'] as String),
      categoryId: map['category_id'] as String,
      categoryName: map['category_name'] as String,
      amountMinor: map['amount_minor'] as int,
    );
  }
}

class _IncomeRecord {
  const _IncomeRecord({required this.eventDateTime, required this.amountMinor});

  final DateTime eventDateTime;
  final int amountMinor;

  factory _IncomeRecord.fromMap(Map<String, Object?> map) {
    return _IncomeRecord(
      eventDateTime: DateTime.parse(map['event_datetime'] as String),
      amountMinor: map['amount_minor'] as int,
    );
  }
}

class _ServiceSpendRecord {
  const _ServiceSpendRecord({
    required this.eventDateTime,
    required this.totalCostMinor,
  });

  final DateTime eventDateTime;
  final int totalCostMinor;

  factory _ServiceSpendRecord.fromMap(Map<String, Object?> map) {
    return _ServiceSpendRecord(
      eventDateTime: DateTime.parse(map['event_datetime'] as String),
      totalCostMinor: map['total_cost_minor'] as int,
    );
  }
}
