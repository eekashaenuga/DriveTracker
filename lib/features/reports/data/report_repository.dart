import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/calculations/analytics_date_range.dart';
import '../../vehicles/domain/vehicle.dart';
import '../../daily_records/domain/income_activity.dart';
import '../../daily_records/domain/income_earnings.dart';
import '../../documents/domain/document_type.dart';
import '../../insights/data/insights_repository.dart';
import '../../insights/presentation/insight_formatters.dart';
import '../domain/report_data.dart';
import '../domain/report_request.dart';

class ReportRepository {
  ReportRepository(this.database, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final AppDatabase database;
  final DateTime Function() clock;
  Future<ReportData> load(ReportRequest request) async {
    final now = clock();
    final db = await database.database;
    return db.transaction((txn) => _read(txn, request, now), exclusive: false);
  }

  Future<ReportData> _read(
    DatabaseExecutor db,
    ReportRequest request,
    DateTime now,
  ) async {
    final vehicleRows = await db.query(
      'vehicles',
      where: 'id = ?',
      whereArgs: [request.vehicleId],
    );
    if (vehicleRows.isEmpty) {
      throw const ReportException(
        'The requested vehicle no longer exists. Select a vehicle and try again.',
      );
    }
    final vehicle = Vehicle.fromMap(vehicleRows.single);
    final range = request.range.resolve(now);
    final insights = await InsightsRepository(database).loadInsights(
      vehicleId: vehicle.id,
      range: request.range,
      now: now,
      executor: db,
    );
    final driving = EarningsSummary(
      insights.incomeActivities.where(
        (r) =>
            r.activity.type == IncomeActivityType.delivery ||
            r.activity.type == IncomeActivityType.rideshare,
      ),
    );
    const money = ReportValueType.money;
    ReportMetric m(
      String label,
      Object? value, {
      ReportValueType type = ReportValueType.text,
      String note = '',
    }) => ReportMetric(label, value, type: type, note: note);
    final unit = vehicle.distanceUnit.shortLabel;
    final metrics = <String, ReportMetric>{
      'operating': m(
        'Recorded operating spend',
        insights.totalSpendMinor,
        type: money,
      ),
      'fuel': m('Fuel spend', insights.fuelSpendMinor, type: money),
      'service': m('Service spend', insights.serviceSpendMinor, type: money),
      'expenses': m('Expense spend', insights.expenseSpendMinor, type: money),
      'acquisition': m(
        'Acquisition included in report period',
        insights.acquisitionCostMinor,
        type: money,
        note: 'Acquisition is separate from operating spend. Undated acquisition costs are included only for All time.',
      ),
      'ownership': m(
        'Recorded ownership spend in report scope',
        insights.ownershipSpendMinor,
        type: money,
        note: 'Operating spend plus acquisition included in this scope; not a lifetime total for bounded periods.',
      ),
      'undated': m(
        'Acquisitions without a recorded date',
        insights.undatedAcquisitionCount,
      ),
      'volume': m('Purchased fuel (L)', insights.fuelVolumeMillilitres / 1000),
      'price': m(
        'Volume-weighted purchase price (p/L)',
        insights.averageFuelPriceMicrosPerLitre == null
            ? null
            : insights.averageFuelPriceMicrosPerLitre! / 10000,
      ),
      'economy': m(
        'Measured full-to-full economy (UK MPG)',
        insights.averageFuelEconomy.ukMpg,
        note:
            insights.averageFuelEconomy.unavailableReason ??
            '${insights.averageFuelEconomy.intervalCount} completed intervals; ${InsightFormat.date(insights.averageFuelEconomy.start)} to ${InsightFormat.date(insights.averageFuelEconomy.end)}.',
      ),
      'distance': m(
        'Observed distance ($unit)',
        insights.distance.value,
        note:
            insights.distance.unavailableReason ??
            '${InsightFormat.date(insights.distance.start)} to ${InsightFormat.date(insights.distance.end)}',
      ),
      'costDistance': m(
        'Operating cost per $unit (GBP)',
        insights.totalCostMinorPerDistance,
        type: money,
        note:
            insights.costDistanceReason ??
            'Coverage-matched recorded spending and distance.',
      ),
      'allIncome': m(
        'All recorded income gross',
        insights.incomeMinor,
        type: money,
      ),
      'gross': m(
        'Driving-activity gross',
        driving.grossMinor,
        type: money,
        note: 'Explicitly saved Rideshare and Delivery activities only.',
      ),
      'linked': m(
        'Driving activities: explicitly linked direct costs',
        driving.recordedCostsMinor,
        type: money,
      ),
      'net': m(
        'Driving activities: net after linked costs',
        driving.netMinor,
        type: money,
        note:
            'Linked costs only; not accounting profit. Costs complete for ${driving.completeCount} of ${driving.count} activities.',
      ),
      'distanceRate': m(
        'Driving gross per $unit (GBP)',
        driving.perDistance(vehicle.distanceUnit),
        type: money,
        note:
            '${driving.distanceCount} of ${driving.count} activities have recorded distance.',
      ),
      'hourRate': m(
        'Driving gross per hour (GBP)',
        driving.perHour(),
        type: money,
        note:
            '${driving.durationCount} of ${driving.count} activities have recorded duration.',
      ),
      'deliveryRate': m(
        'Driving gross per delivery (GBP)',
        driving.perDelivery,
        type: money,
        note:
            '${driving.deliveryCount} of ${driving.count} activities have recorded delivery counts.',
      ),
      'netDistanceRate': m(
        'Driving net per $unit (GBP)',
        driving.netMinor == null
            ? null
            : driving.perDistance(vehicle.distanceUnit, net: true),
        type: money,
      ),
      'netHourRate': m(
        'Driving net per hour (GBP)',
        driving.netMinor == null ? null : driving.perHour(net: true),
        type: money,
      ),
    };
    final identity = <ReportMetric>[
      m('Vehicle', vehicle.name),
      m('Registration', vehicle.registration),
      m('Make / model', '${vehicle.make} ${vehicle.model}'),
      m('Year', vehicle.year),
      m('Fuel', vehicle.fuelType.label),
      m('Distance unit', unit),
      m('Archived vehicle', vehicle.isArchived ? 'Yes' : 'No'),
      m(
        'Purchase date (vehicle context)',
        vehicle.purchaseDate,
        type: ReportValueType.date,
      ),
      m('Purchase mileage (vehicle context)', vehicle.purchaseMileage),
      m(
        'Purchase price (vehicle context)',
        vehicle.acquisitionCostMinor,
        type: money,
        note: 'The summary counts only acquisition included in this report scope.',
      ),
      if (request.includeSensitive) ...[
        m('VIN', vehicle.vin),
        m('Seller', vehicle.seller),
        m('Vehicle notes', vehicle.notes),
      ],
    ];
    final conditions = <String>['vehicle_id = ?'];
    final args = <Object?>[vehicle.id];
    if (range.startInclusive != null) {
      conditions.add('event_datetime >= ?');
      args.add(range.startInclusive!.toUtc().toIso8601String());
    }
    if (range.endExclusive != null) {
      conditions.add('event_datetime < ?');
      args.add(range.endExclusive!.toUtc().toIso8601String());
    }
    final where = conditions.join(' AND ');
    Future<List<Map<String, Object?>>> rows(String table) => db.query(
      table,
      where: where,
      whereArgs: args,
      orderBy: 'event_datetime ASC, id ASC',
    );
    final cats = {
      for (final c in await db.query('record_categories')) c['id']: c,
    };
    String category(Object? id) =>
        (cats[id]?['name'] as String?) ?? 'Category unavailable';
    DateTime date(Object? value) => DateTime.parse(value as String);
    String utc(Object? value) => date(value).toUtc().toIso8601String();
    ReportColumn c(
      String name, {
      ReportValueType type = ReportValueType.text,
      int precision = 2,
      double width = 24,
    }) => ReportColumn(name, type: type, precision: precision, width: width);
    final dt = c('Local date/time', type: ReportValueType.timestamp);
    final odo = c('Odometer', type: ReportValueType.number, precision: 0);
    final notes = c('Notes', width: 45);
    final id = c('Record ID', width: 35);
    final tables = <ReportTable>[];
    if (request.sections.contains(ReportSection.fuel)) {
      tables.add(
        ReportTable(
          'Fuel',
          [
            dt,
            odo,
            c('Unit'),
            c('Fuel type'),
            c('Litres', type: ReportValueType.number, precision: 3),
            c('Total cost GBP', type: money),
            c('Unit price p/L', type: ReportValueType.number, precision: 4),
            c('Tank'),
            c('Missed previous refuel'),
            c('Station'),
            notes,
            c('UTC timestamp'),
            id,
          ],
          (await rows('refuels')).map(
            (r) => [
              date(r['event_datetime']),
              r['odometer'],
              unit,
              FuelType.fromStorage(r['fuel_type'] as String).label,
              (r['volume_millilitres'] as int) / 1000,
              r['total_cost_minor'],
              (r['unit_price_micros_per_litre'] as int) / 10000,
              r['is_full_tank'] == 1 ? 'Full' : 'Partial',
              r['missed_previous_refuel'] == 1 ? 'Yes' : 'No',
              r['station'],
              r['notes'],
              utc(r['event_datetime']),
              r['id'],
            ],
          ),
        ),
      );
    }
    if (request.sections.contains(ReportSection.services)) {
      final services = await rows('services');
      tables.add(
        ReportTable(
          'Services',
          [
            dt,
            odo,
            c('Unit'),
            c('Record kind'),
            c('Garage / provider'),
            c('Total service cost GBP', type: money),
            notes,
            c('UTC timestamp'),
            c('Service ID'),
          ],
          services.map(
            (r) => [
              date(r['event_datetime']),
              r['odometer'],
              unit,
              r['is_baseline'] == 1
                  ? 'Maintenance baseline (not spending)'
                  : 'Service',
              r['garage'],
              r['is_baseline'] == 1 ? null : r['total_cost_minor'],
              r['notes'],
              utc(r['event_datetime']),
              r['id'],
            ],
          ),
        ),
      );
      final items = await db.rawQuery(
        'SELECT si.* FROM service_items si JOIN services s ON s.id=si.service_id WHERE ${conditions.map((v) => 's.$v').join(' AND ')} ORDER BY s.event_datetime,si.id',
        args,
      );
      tables.add(
        ReportTable(
          'Service Items',
          [
            c('Service ID'),
            c('Item name'),
            c('Allocated cost GBP', type: money),
            notes,
            c('Item ID'),
          ],
          items.map(
            (r) => [
              r['service_id'],
              r['item_name'],
              r['allocated_cost_minor'],
              r['notes'],
              r['id'],
            ],
          ),
        ),
      );
    }
    if (request.sections.contains(ReportSection.expenses)) {
      tables.add(
        ReportTable(
          'Expenses',
          [
            dt,
            c('Category'),
            c('Category archived'),
            c('Amount GBP', type: money),
            odo,
            c('Unit'),
            c('Merchant'),
            c('Payment method'),
            notes,
            c('UTC timestamp'),
            c('Expense ID'),
          ],
          (await rows('expenses')).map(
            (r) => [
              date(r['event_datetime']),
              category(r['category_id']),
              cats[r['category_id']]?['is_archived'] == 1 ? 'Yes' : 'No',
              r['amount_minor'],
              r['odometer'],
              unit,
              r['merchant'],
              r['payment_method'],
              r['notes'],
              utc(r['event_datetime']),
              r['id'],
            ],
          ),
        ),
      );
    }
    if (request.sections.contains(ReportSection.income)) {
      final earnings = {
        for (final e in insights.incomeActivities) e.income.id: e,
      };
      tables.add(
        ReportTable(
          'Income Activities',
          [
            dt,
            c('Saved activity type'),
            c('Category'),
            c('Source'),
            c('Canonical gross GBP', type: money),
            c('Base GBP', type: money),
            c('Tips GBP', type: money),
            c('Travel GBP', type: money),
            c('Other GBP', type: money),
            c('Activity distance', type: ReportValueType.number, precision: 3),
            c('Distance unit'),
            c('Raw distance mm', type: ReportValueType.number, precision: 0),
            c('Duration minutes', type: ReportValueType.number, precision: 0),
            c('Deliveries', type: ReportValueType.number, precision: 0),
            c(
              'Reimbursement rate GBP',
              type: ReportValueType.number,
              precision: 6,
            ),
            c('Rate unit'),
            c('Direct costs complete'),
            c('Linked costs GBP', type: money),
            c('Available net GBP', type: money),
            odo,
            notes,
            c('UTC timestamp'),
            c('Income ID'),
          ],
          (await rows('income_records')).map((r) {
            final a = IncomeActivity.fromMap(r);
            final e = earnings[r['id']]!;
            return [
              date(r['event_datetime']),
              a.type.label,
              category(r['category_id']),
              r['source'],
              r['amount_minor'],
              a.baseMinor,
              a.tipsMinor,
              a.travelMinor,
              a.otherMinor,
              a.distanceMm == null
                  ? null
                  : ActivityDistance.value(a.distanceMm!, vehicle.distanceUnit),
              unit,
              a.distanceMm,
              a.durationMinutes,
              a.deliveryCount,
              a.rateMicros == null ? null : a.rateMicros! / 1000000,
              a.rateUnit?.shortLabel,
              a.directCostsComplete ? 'Yes' : 'No',
              e.directCostsMinor,
              e.netMinor,
              r['odometer'],
              r['notes'],
              utc(r['event_datetime']),
              r['id'],
            ];
          }),
        ),
      );
      final links = await db.rawQuery(
        'SELECT l.income_id,e.* FROM income_activity_expenses l JOIN income_records i ON i.id=l.income_id JOIN expenses e ON e.id=l.expense_id WHERE ${conditions.map((v) => 'i.$v').join(' AND ')} ORDER BY i.event_datetime,e.id',
        args,
      );
      tables.add(
        ReportTable(
          'Linked Costs',
          [
            c('Income ID'),
            c('Expense ID'),
            c('Expense date', type: ReportValueType.timestamp),
            c('Category'),
            c('Merchant'),
            c('Amount GBP', type: money),
            c('Outside report period'),
          ],
          links.map(
            (r) => [
              r['income_id'],
              r['id'],
              date(r['event_datetime']),
              category(r['category_id']),
              r['merchant'],
              r['amount_minor'],
              range.contains(date(r['event_datetime'])) ? 'No' : 'Yes',
            ],
          ),
          caption: 'Relationship context for selected activities. Out-of-period expenses are not added to period operating spend.',
        ),
      );
    }
    if (request.sections.contains(ReportSection.odometer)) {
      tables.add(
        ReportTable(
          'Odometer',
          [
            dt,
            c('Reading', type: ReportValueType.number, precision: 0),
            c('Unit'),
            c('Source type'),
            c('Source record ID'),
            c('UTC timestamp'),
            c('Entry ID'),
          ],
          (await rows('odometer_entries')).map(
            (r) => [
              date(r['event_datetime']),
              r['odometer'],
              unit,
              r['source_type'],
              r['source_record_id'],
              utc(r['event_datetime']),
              r['id'],
            ],
          ),
          caption: 'Recorded readings, including source-linked entries. Readings are never summed.',
        ),
      );
    }
    if (request.sections.contains(ReportSection.documents)) {
      final docs = await db.query(
        'documents',
        where: 'vehicle_id = ?',
        whereArgs: [vehicle.id],
        orderBy: 'is_archived,title,id',
      );
      tables.add(
        ReportTable(
          'Documents',
          [
            c('Category / type'),
            c('Title'),
            c('Issue date', type: ReportValueType.date),
            c('Due / expiry date', type: ReportValueType.date),
            c('Date meaning'),
            c('Provider'),
            c('Reference'),
            notes,
            c('Archived'),
            c('Document ID'),
          ],
          docs.map(
            (r) => [
              r['category'],
              r['title'],
              r['issue_date'] == null ? null : date(r['issue_date']),
              r['expiry_date'] == null ? null : date(r['expiry_date']),
              DocumentType.classify(r['category'] as String).dateLabel,
              r['provider'],
              request.includeSensitive ? r['reference_number'] : null,
              request.includeSensitive ? r['notes'] : null,
              r['is_archived'] == 1 ? 'Yes' : 'No',
              r['id'],
            ],
          ),
          caption: 'Current recorded document register as of generation, including archived entries; not filtered by transaction period. No attachment files are included.',
        ),
      );
    }
    return ReportData(
      vehicleName: vehicle.name,
      period: range.preset == AnalyticsRangePreset.all
          ? 'All time'
          : InsightFormat.range(range.startInclusive!, range.endInclusive!),
      generatedAt: now.toUtc(),
      timezone:
          '${now.toLocal().timeZoneName} (UTC offset ${now.toLocal().timeZoneOffset}); transaction dates use local calendar boundaries.',
      identity: identity,
      metrics: metrics,
      tables: tables,
      breakdown: [
        for (final b in insights.breakdown)
          m(b.label, b.amountMinor, type: money),
      ],
      recordCount: tables
          .where(
            (t) =>
                t.name != 'Service Items' &&
                t.name != 'Linked Costs' &&
                t.name != 'Documents',
          )
          .fold(0, (n, t) => n + t.rows.length),
    );
  }
}
