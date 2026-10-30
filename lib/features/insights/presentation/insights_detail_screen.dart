import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_motion.dart';
import '../../../core/calculations/analytics_date_range.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/utilities/money.dart';
import '../../daily_records/domain/daily_activity.dart';
import '../../daily_records/domain/history_filter.dart';
import '../../daily_records/domain/income_activity.dart';
import '../../daily_records/domain/refuel.dart';
import '../../vehicles/domain/vehicle.dart';
import '../domain/vehicle_insights.dart';
import 'income_activity_earnings_panel.dart';
import 'insight_components.dart';
import 'insight_formatters.dart';
import 'insight_recorded_values.dart';
import 'insight_visuals.dart';

enum InsightDetailKind { costs, fuel, earnings }

class InsightsDetailScreen extends StatefulWidget {
  const InsightsDetailScreen({
    required this.kind,
    required this.insights,
    required this.range,
    required this.activityFilter,
    required this.earningsUnit,
    required this.onActivityFilterChanged,
    required this.onEarningsUnitChanged,
    super.key,
  });
  final InsightDetailKind kind;
  final VehicleInsights insights;
  final AnalyticsDateRange range;
  final String activityFilter;
  final DistanceUnit earningsUnit;
  final ValueChanged<String> onActivityFilterChanged;
  final ValueChanged<DistanceUnit> onEarningsUnitChanged;
  @override
  State<InsightsDetailScreen> createState() => _InsightsDetailScreenState();
}

class _InsightsDetailScreenState extends State<InsightsDetailScreen> {
  int? _revision;
  Future<VehicleInsights>? _future;
  Future<List<({Refuel record, String vehicle})>>? _fuelHistory;
  late VehicleInsights _latest = widget.insights;
  late String _filter = widget.activityFilter;
  late DistanceUnit _unit = widget.earningsUnit;
  bool _price = true;
  int? _bucket;
  String? _category;
  String money(int n) => DTFormatters.moneyMinor(n);
  String day(DateTime? at) => InsightFormat.date(at);
  String get title => switch (widget.kind) {
    InsightDetailKind.costs => 'Costs',
    InsightDetailKind.fuel => 'Fuel',
    InsightDetailKind.earnings => 'Earnings',
  };
  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriveTrackerController>();
    if (_revision != c.dataRevision || _future == null) {
      final initial = _revision == null;
      _revision = c.dataRevision;
      final id =
          c.activeVehicles.any((v) => v.id == widget.insights.scope.vehicle?.id)
          ? widget.insights.scope.vehicle?.id
          : null;
      _future = initial
          ? Future.value(widget.insights)
          : c.insightsFor(vehicleId: id, range: widget.range);
      if (widget.kind == InsightDetailKind.fuel) {
        _fuelHistory = _loadFuelHistory(c, id);
      }
    }
    return Scaffold(
      key: Key('insightsDetail_${widget.kind.name}'),
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'About these insights',
            icon: const Icon(Icons.info_outline),
            onPressed: () =>
                showInsightInformation(context, title, switch (widget.kind) {
                  InsightDetailKind.costs => 'Operating spend is recorded fuel, non-baseline services and expenses. Linked expenses count once; service allocations are not extra costs. Acquisition is separate. Costs may mix personal and earning-related use. Separately entered duplicate invoices cannot be identified automatically. Cost/distance is available only when spending and observed-distance coverage match.',
                  InsightDetailKind.fuel => 'Purchase price is weighted by recorded fuel volume. Full-to-full economy excludes the opening fill and includes partial fills until the closing full fill. Missed history resets coverage. Intervals are included by their closing-fill date and can begin before this range. Purchased fuel is not necessarily fuel consumed in the selected period. No mileage is interpolated.',
                  InsightDetailKind.earnings => 'Gross is the recorded amount received. Net after linked direct costs subtracts only explicitly linked expenses and is unavailable if included costs are incomplete. It is not profit. No fuel, service or acquisition costs are allocated automatically. Rates use matching eligible records. Activity costs follow the income date; ordinary expenses follow their own dates. Work/Salary is associated work income, not vehicle-generated profit.',
                }),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          key: Key('insights${title}DetailList'),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            FutureBuilder<VehicleInsights>(
              key: ValueKey(_revision),
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      const Text(
                        'Could not load insights. Your records are unchanged.',
                      ),
                      TextButton(
                        onPressed: () => setState(() => _future = null),
                        child: const Text('Retry'),
                      ),
                    ],
                  );
                }
                if (snapshot.connectionState != ConnectionState.done ||
                    snapshot.data == null) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: CircularProgressIndicator(
                        key: Key('insightsDetailLoading'),
                      ),
                    ),
                  );
                }
                _latest = snapshot.data!;
                final range = _latest.range;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${_latest.scope.vehicle?.name ?? 'All active vehicles'} · ${insightPeriodLabel(widget.range)}',
                      key: const Key('insightsDetailContext'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (range.isBounded)
                      Text(
                        '${day(range.startInclusive)} – ${day(range.endInclusive)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 20),
                    switch (widget.kind) {
                      InsightDetailKind.costs => _costs(),
                      InsightDetailKind.fuel => _fuel(),
                      InsightDetailKind.earnings => IncomeActivityEarningsPanel(
                        vehicleNames: {
                          for (final v in c.activeVehicles) v.id: v.name,
                        },
                        records: _latest.incomeActivities,
                        unit: _latest.scope.distanceUnit,
                        initialFilter: _filter,
                        initialDisplayUnit: _unit,
                        buckets: _latest.spendingBuckets,
                        onFilterChanged: (v) {
                          setState(() => _filter = v);
                          widget.onActivityFilterChanged(v);
                        },
                        onDisplayUnitChanged: (v) {
                          setState(() => _unit = v);
                          widget.onEarningsUnitChanged(v);
                        },
                        onOpenHistory: (types, b) => history(
                          type: DailyActivityType.income,
                          activityTypes: types,
                          bucket: b,
                        ),
                      ),
                    },
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void history({
    DailyActivityType type = DailyActivityType.all,
    String? category,
    bool costs = false,
    Set<IncomeActivityType>? activityTypes,
    InsightAmountBucket? bucket,
  }) {
    AppNavigation.openHistory(
      context,
      filter: HistoryFilter(
        vehicleId: _latest.scope.vehicle?.id,
        vehicleIds: _latest.scope.isAllVehicles ? _latest.vehicleIds : null,
        range: bucket == null
            ? widget.range
            : AnalyticsDateRange.custom(
                start: bucket.startInclusive,
                endInclusive: DateTime(
                  bucket.endExclusive.year,
                  bucket.endExclusive.month,
                  bucket.endExclusive.day - 1,
                ),
              ),
        type: type,
        categoryId: category,
        recordTypes: costs
            ? const {
                DailyActivityType.refuel,
                DailyActivityType.service,
                DailyActivityType.expense,
              }
            : null,
        operatingCostsOnly: costs,
        activityTypes: activityTypes,
      ),
    );
  }

  Future<List<({Refuel record, String vehicle})>> _loadFuelHistory(
    DriveTrackerController c,
    String? id,
  ) async {
    final rows = await c.history(
      HistoryFilter(
        vehicleId: id,
        vehicleIds: id == null
            ? c.activeVehicles.map((v) => v.id).toList()
            : null,
        range: widget.range,
        type: DailyActivityType.refuel,
      ),
    );
    final result = <({Refuel record, String vehicle})>[];
    for (final row in rows.take(3)) {
      final record = await c.refuelById(row.recordId);
      if (record != null) {
        result.add((record: record, vehicle: row.vehicleName ?? 'Vehicle'));
      }
    }
    return result;
  }

  Widget _disclosure(String key, String label, List<Widget> children) =>
      ExpansionTile(
        key: PageStorageKey(key),
        tilePadding: EdgeInsets.zero,
        expansionAnimationStyle: DTMotion.reduceMotionOf(context)
            ? AnimationStyle.noAnimation
            : null,
        title: Text(label),
        childrenPadding: const EdgeInsets.only(bottom: 4),
        children: children,
      );
  Widget _costs() {
    final i = _latest;
    final c = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsightMetricTile(
          key: const Key('insightsCostsTotalMetric'),
          label: 'Total recorded operating spend',
          value: money(i.totalSpendMinor),
          icon: Icons.account_balance_wallet_outlined,
          hero: true,
          caption: 'Fuel, service & expenses · acquisition excluded',
        ),
        const SizedBox(height: 12),
        InsightMetricGrid(
          tiles: [
            InsightMetricTile(
              key: const Key('insightsFuelSpendMetric'),
              label: 'Fuel',
              value: money(i.fuelSpendMinor),
              icon: Icons.local_gas_station_outlined,
            ),
            InsightMetricTile(
              key: const Key('insightsServiceSpendMetric'),
              label: 'Service',
              value: money(i.serviceSpendMinor),
              icon: Icons.build_outlined,
              tone: InsightTone.warm,
            ),
            InsightMetricTile(
              key: const Key('insightsExpenseSpendMetric'),
              label: 'Expenses',
              value: money(i.expenseSpendMinor),
              icon: Icons.receipt_long_outlined,
              tone: InsightTone.rose,
            ),
          ],
        ),
        if (i.totalSpendMinor > 0) ...[
          const InsightSectionTitle('Recorded costs over time · GBP'),
          DTInsightCard(
            key: const Key('insightsSpendingChart'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (i.spendingBuckets.length == 1)
                  Text(
                    'One recorded period · ${money(i.spendingBuckets.single.totalSpendMinor)}',
                  )
                else
                  DTInsightBarChart(
                    bars: [
                      for (final b in i.spendingBuckets)
                        DTInsightBarDatum(
                          index: b.index,
                          label: b.label,
                          value: b.totalSpendMinor,
                          valueLabel: money(b.totalSpendMinor),
                          semanticsLabel:
                              '${b.label}: Fuel ${money(b.fuelSpendMinor)}, Service ${money(b.serviceSpendMinor)}, Expenses ${money(b.expenseSpendMinor)}; total ${money(b.totalSpendMinor)}',
                          color: c.primary,
                          components: [
                            (value: b.fuelSpendMinor, color: c.primary),
                            (value: b.serviceSpendMinor, color: c.tertiary),
                            (value: b.expenseSpendMinor, color: c.error),
                          ],
                          selected: _bucket == b.index,
                          onTap: () => setState(() => _bucket = b.index),
                        ),
                    ],
                    maxValue: i.spendingBuckets.fold<int>(
                      0,
                      (v, b) => b.totalSpendMinor > v ? b.totalSpendMinor : v,
                    ),
                    barKeyPrefix: 'insightsSpendingBucket',
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    for (final entry in [
                      (c.primary, 'Fuel'),
                      (c.tertiary, 'Service'),
                      (c.error, 'Expenses'),
                    ])
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, color: entry.$1, size: 8),
                          const SizedBox(width: 6),
                          Text(entry.$2),
                        ],
                      ),
                  ],
                ),
                _disclosure('costPeriodTotals', 'Period totals', [
                  for (final b in i.spendingBuckets)
                    ListTile(
                      title: Text('${b.label} · ${money(b.totalSpendMinor)}'),
                      subtitle: Text(
                        'Fuel ${money(b.fuelSpendMinor)} · Service ${money(b.serviceSpendMinor)} · Expenses ${money(b.expenseSpendMinor)}',
                      ),
                      onTap: () => setState(() => _bucket = b.index),
                    ),
                ]),
                if (_bucket != null && _bucket! < i.spendingBuckets.length) ...[
                  Text(
                    '${i.spendingBuckets[_bucket!].label} · ${money(i.spendingBuckets[_bucket!].totalSpendMinor)} spent',
                    key: const Key('insightsSelectedSpendingBucket'),
                  ),
                  TextButton(
                    key: const Key('insightsBucketDrilldownButton'),
                    onPressed: () => history(
                      costs: true,
                      bucket: i.spendingBuckets[_bucket!],
                    ),
                    child: const Text('View records'),
                  ),
                ],
              ],
            ),
          ),
          const InsightSectionTitle('Spending breakdown'),
          Column(
            key: const Key('insightsBreakdown'),
            children: [
              for (final b in i.breakdown)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InsightRankedRow(
                      key: Key('insightsBreakdown_${b.key}'),
                      label: b.label,
                      value: money(b.amountMinor),
                      share:
                          '${(100 * b.amountMinor / i.totalSpendMinor).toStringAsFixed(1)}%',
                      fraction: b.amountMinor / i.breakdown.first.amountMinor,
                      tone: b.type == DailyActivityType.service
                          ? InsightTone.warm
                          : InsightTone.teal,
                      accent: b.type == DailyActivityType.expense
                          ? insightCategoryAccent(
                              context,
                              b.categoryId ?? b.key,
                            )
                          : null,
                      onTap: () => setState(() => _category = b.key),
                    ),
                    if (_category == b.key)
                      TextButton(
                        key: const Key('insightsBreakdownDrilldownButton'),
                        onPressed: () => history(
                          type: b.type,
                          category: b.categoryId,
                          costs: true,
                        ),
                        child: const Text('View records'),
                      ),
                  ],
                ),
            ],
          ),
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('No recorded costs in this range.'),
          ),
        const InsightSectionTitle('Acquisition & ownership'),
        InsightMetricGrid(
          maxColumns: 2,
          tiles: [
            InsightMetricTile(
              key: const Key('insightsAcquisitionMetric'),
              label: 'Acquisition cost',
              value: i.acquisitionCount == 0
                  ? 'Not recorded in range'
                  : money(i.acquisitionCostMinor),
              icon: Icons.directions_car_outlined,
              tone: InsightTone.neutral,
              caption: 'Separate from operating spend',
            ),
            InsightMetricTile(
              key: const Key('insightsOwnershipMetric'),
              label: 'Total ownership spend',
              value: money(i.ownershipSpendMinor),
              icon: Icons.account_balance_outlined,
              tone: InsightTone.neutral,
              caption: 'Operating spend + recorded acquisition',
            ),
          ],
        ),
        _disclosure('costCoverage', 'Distance & coverage', [
          ListTile(
            key: const Key('insightsDistanceMetric'),
            title: const Text('Observed distance'),
            subtitle: Text(
              i.distance.value == null
                  ? i.distance.unavailableReason ?? 'Not enough data'
                  : '${InsightFormat.distance(i.distance.value)} ${i.distance.unit!.shortLabel}\n${day(i.distance.start)} – ${day(i.distance.end)}; no mileage is interpolated.',
            ),
          ),
          ListTile(
            key: const Key('insightsCostPerDistanceMetric'),
            title: const Text('Recorded operating cost / distance'),
            subtitle: Text(
              '${InsightFormat.costPerDistance(i.totalCostMinorPerDistance, i.scope.distanceUnit)}\n${i.costDistanceReason ?? 'Matching recorded coverage.'}',
            ),
          ),
        ]),
        TextButton.icon(
          onPressed: () => showInsightInformation(
            context,
            'Acquisition & ownership',
            'Purchase prices are separate from operating spend. Undated purchases count only in All time. Total ownership spend adds recorded acquisition in this range and does not deduct income.',
          ),
          icon: const Icon(Icons.info_outline, size: 18),
          label: const Text('What is included?'),
        ),
      ],
    );
  }

  Widget _fuel() {
    final i = _latest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsightMetricGrid(
          maxColumns: 2,
          tiles: [
            InsightMetricTile(
              key: const Key('insightsFuelRecordedMetric'),
              label: 'Fuel spend',
              value: money(i.fuelSpendMinor),
              icon: Icons.payments_outlined,
            ),
            InsightMetricTile(
              key: const Key('insightsFuelVolumeMetric'),
              label: 'Purchased volume',
              value: InsightFormat.litres(i.fuelVolumeMillilitres),
              icon: Icons.water_drop_outlined,
              tone: InsightTone.warm,
            ),
            InsightMetricTile(
              key: const Key('insightsFuelPriceMetric'),
              label: 'Avg purchase price',
              value: InsightFormat.price(i.averageFuelPriceMicrosPerLitre),
              icon: Icons.sell_outlined,
              tone: InsightTone.neutral,
              caption: 'Volume-weighted',
            ),
            InsightMetricTile(
              key: const Key('insightsFuelEconomyMetric'),
              label: 'Full-to-full economy',
              value: InsightFormat.economy(i.averageFuelEconomy.ukMpg),
              icon: Icons.route_outlined,
              tone: InsightTone.mint,
              caption: i.averageFuelEconomy.ukMpg == null
                  ? 'Not enough eligible data'
                  : '${i.averageFuelEconomy.intervalCount} completed intervals',
            ),
          ],
        ),
        const SizedBox(height: 24),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Price')),
            ButtonSegment(value: false, label: Text('Economy')),
          ],
          selected: {_price},
          onSelectionChanged: (v) => setState(() => _price = v.single),
        ),
        const SizedBox(height: 16),
        _fuelTrend(),
        _disclosure('fuelCoverage', 'Coverage & details', [
          Text(
            i.averageFuelEconomy.unavailableReason ??
                '${day(i.averageFuelEconomy.start)} – ${day(i.averageFuelEconomy.end)}. Intervals use the closing-fill date and can start before this range.',
          ),
          const Text('No mileage is interpolated.'),
          const Text(
            'Purchased volume is not necessarily consumption in this period.',
          ),
          ListTile(
            key: const Key('insightsFuelCostPerDistanceMetric'),
            visualDensity: VisualDensity.compact,
            minTileHeight: 48,
            title: const Text('Recorded fuel cost / distance'),
            subtitle: Text(
              '${InsightFormat.costPerDistance(i.fuelCostMinorPerDistance, i.scope.distanceUnit)}\n${i.costDistanceReason ?? 'Matching recorded coverage; not a trip estimate.'}',
            ),
          ),
        ]),
        InsightSectionTitle(
          'Recent fills',
          action: 'View all',
          onAction: () => history(type: DailyActivityType.refuel),
        ),
        FutureBuilder<List<({Refuel record, String vehicle})>>(
          future: _fuelHistory,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text(
                'Fuel history is unavailable. Use View all to retry in History.',
              );
            }
            if (snapshot.data == null) return const LinearProgressIndicator();
            if (snapshot.data!.isEmpty) {
              return const Text('No fills recorded in this range.');
            }
            return Column(
              children: [
                for (final entry in snapshot.data!)
                  ListTile(
                    visualDensity: VisualDensity.compact,
                    minTileHeight: 64,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${day(entry.record.eventDateTime)} · ${money(entry.record.totalCostMinor)}',
                    ),
                    subtitle: Text(
                      '${entry.record.station ?? 'Refuel'}${i.scope.isAllVehicles ? ' · ${entry.vehicle}' : ''}\n${InsightFormat.litres(entry.record.volumeMillilitres)} · ${InsightFormat.price(entry.record.unitPriceMicrosPerLitre)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => AppNavigation.openRecordDetails(
                      context,
                      DailyActivityType.refuel,
                      entry.record.id,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _fuelTrend() {
    final i = _latest;
    if (!_price && i.scope.isAllVehicles) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Select one vehicle for measured economy. Vehicle odometers and MPG are not combined.',
        ),
      );
    }
    final points = _price
        ? [
            for (final p in i.fuelPriceTrend)
              DTInsightLinePoint(
                date: p.date,
                label: InsightFormat.date(p.date, compact: true),
                value: p.microsPerLitre / FuelNumbers.microsPerPence,
                valueLabel: InsightFormat.price(p.microsPerLitre),
                detailLabel: day(p.date),
                semanticsLabel:
                    '${day(p.date)}: ${InsightFormat.price(p.microsPerLitre)}',
              ),
          ]
        : [
            for (final p in i.fuelEconomyTrend)
              DTInsightLinePoint(
                date: p.date,
                label: InsightFormat.date(p.date, compact: true),
                value: p.ukMpg,
                valueLabel: InsightFormat.economy(p.ukMpg),
                detailLabel:
                    '${day(p.date)} · ${InsightFormat.distance(p.distance)} ${i.scope.distanceUnit!.shortLabel} · ${InsightFormat.litres(p.volumeMillilitres)}',
                observationDetail:
                    '${InsightFormat.distance(p.distance)} ${i.scope.distanceUnit!.shortLabel} · ${InsightFormat.litres(p.volumeMillilitres)}',
                semanticsLabel:
                    '${day(p.date)}: ${InsightFormat.economy(p.ukMpg)}',
              ),
          ];
    if (points.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('Not enough data for this fuel trend.'),
      );
    }
    return DTInsightCard(
      key: Key(_price ? 'insightsFuelPriceChart' : 'insightsFuelEconomyChart'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _price
                ? 'Purchase price · pence/litre'
                : 'Measured economy · UK MPG',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (points.length == 1)
            Text(
              'One recorded observation: ${points.single.detailLabel} · ${points.single.valueLabel}',
            )
          else
            DTInsightLineChart(
              points: points,
              color: Theme.of(context).colorScheme.primary,
              pointKeyPrefix: _price
                  ? 'insightsFuelPricePoint'
                  : 'insightsFuelEconomyPoint',
              selectedDetailKey: Key(
                _price
                    ? 'insightsSelectedFuelPricePoint'
                    : 'insightsSelectedFuelEconomyPoint',
              ),
            ),
          const SizedBox(height: 8),
          const Text('Recorded observations at their actual dates.'),
          InsightRecordedValues(
            points: points,
            kind: _price ? 'Price' : 'Economy',
          ),
        ],
      ),
    );
  }
}
