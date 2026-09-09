import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/calculations/analytics_date_range.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/utilities/money.dart';
import '../../../shared/widgets/analytics_date_range_picker.dart';
import '../../../shared/widgets/dt_empty_state.dart';
import '../../daily_records/domain/daily_activity.dart';
import '../../daily_records/domain/history_filter.dart';
import '../../vehicles/domain/vehicle.dart';
import 'insight_visuals.dart';
import '../domain/vehicle_insights.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  String? _vehicleId;
  var _range = AnalyticsDateRange.month;
  Future<VehicleInsights>? _future;
  String? _loadedSignature;
  bool _initializedScope = false;
  int? _selectedBucketIndex;
  String? _selectedBreakdownKey;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    final vehicles = controller.activeVehicles;
    if (!_initializedScope) {
      _initializedScope = true;
      _vehicleId = controller.selectedVehicle?.id;
    }

    if (vehicles.isEmpty) {
      return const Scaffold(
        body: SafeArea(
          child: DTEmptyState(
            icon: Icons.insights_rounded,
            title: 'No active vehicles',
            body: 'Add a vehicle before reviewing Insights.',
          ),
        ),
      );
    }

    _ensureFuture(controller);

    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<VehicleInsights>(
          future: _future,
          builder: (context, snapshot) {
            final insights = snapshot.data;
            if (insights == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return _InsightsBody(
              insights: insights,
              vehicles: vehicles,
              selectedVehicleId: _vehicleId,
              range: _range,
              selectedBucketIndex: _selectedBucketIndex,
              selectedBreakdownKey: _selectedBreakdownKey,
              onVehicleChanged: (vehicleId) {
                setState(() {
                  _vehicleId = vehicleId;
                  _selectedBucketIndex = null;
                  _selectedBreakdownKey = null;
                  _loadedSignature = null;
                });
              },
              onRangeChanged: (range) {
                setState(() {
                  _range = range;
                  _selectedBucketIndex = null;
                  _selectedBreakdownKey = null;
                  _loadedSignature = null;
                });
              },
              onCustomRangeRequested: _showCustomRangeDialog,
              onBucketSelected: (index) {
                setState(() => _selectedBucketIndex = index);
              },
              onBreakdownSelected: (key) {
                setState(() => _selectedBreakdownKey = key);
              },
              onOpenHistory: _openHistory,
            );
          },
        ),
      ),
    );
  }

  void _ensureFuture(DriveTrackerController controller) {
    final signature = [
      _vehicleId ?? 'all',
      _range.preset.name,
      _range.customStart?.toIso8601String() ?? '',
      _range.customEndInclusive?.toIso8601String() ?? '',
    ].join('|');
    if (_future == null || _loadedSignature != signature) {
      _loadedSignature = signature;
      _future = controller.insightsFor(vehicleId: _vehicleId, range: _range);
    }
  }

  Future<void> _showCustomRangeDialog() async {
    final controller = context.read<DriveTrackerController>();
    final range = await pickAnalyticsDateRange(
      context: context,
      currentRange: _range,
      currentDate: controller.currentTime,
      pickerKey: const Key('insightsCustomRangePicker'),
      helpText: 'Select insights range',
    );
    if (range == null || !mounted) {
      return;
    }
    setState(() {
      _range = range;
      _selectedBucketIndex = null;
      _selectedBreakdownKey = null;
      _loadedSignature = null;
    });
  }

  void _openHistory(HistoryFilter filter) {
    AppNavigation.openHistory(context, filter: filter);
  }
}

class _InsightsBody extends StatelessWidget {
  const _InsightsBody({
    required this.insights,
    required this.vehicles,
    required this.selectedVehicleId,
    required this.range,
    required this.selectedBucketIndex,
    required this.selectedBreakdownKey,
    required this.onVehicleChanged,
    required this.onRangeChanged,
    required this.onCustomRangeRequested,
    required this.onBucketSelected,
    required this.onBreakdownSelected,
    required this.onOpenHistory,
  });

  final VehicleInsights insights;
  final List<Vehicle> vehicles;
  final String? selectedVehicleId;
  final AnalyticsDateRange range;
  final int? selectedBucketIndex;
  final String? selectedBreakdownKey;
  final ValueChanged<String?> onVehicleChanged;
  final ValueChanged<AnalyticsDateRange> onRangeChanged;
  final VoidCallback onCustomRangeRequested;
  final ValueChanged<int> onBucketSelected;
  final ValueChanged<String> onBreakdownSelected;
  final ValueChanged<HistoryFilter> onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final selectedBucket = _selectedBucket();
    final selectedBreakdown = _selectedBreakdown();
    final historyVehicleId = insights.scope.isAllVehicles
        ? null
        : insights.scope.vehicle?.id;
    return ListView(
      key: const Key('insightsScreenList'),
      padding: const EdgeInsets.fromLTRB(
        DTSpacing.lg,
        DTSpacing.lg,
        DTSpacing.lg,
        DTSpacing.xxxl,
      ),
      children: [
        _Header(
          vehicles: vehicles,
          selectedVehicleId: selectedVehicleId,
          range: range,
          onVehicleChanged: onVehicleChanged,
          onRangeChanged: onRangeChanged,
          onCustomRangeRequested: onCustomRangeRequested,
        ),
        const SizedBox(height: DTSpacing.lg),
        _SummaryPanel(insights: insights),
        if (!insights.hasAnyData) ...[
          const SizedBox(height: DTSpacing.xl),
          const DTEmptyState(
            icon: Icons.query_stats_rounded,
            title: 'No insights yet',
            body: 'Add real fuel, expense, income, service or odometer records to build charts.',
          ),
        ] else ...[
          const _InsightSectionHeader(title: 'Spending over time'),
          _SpendingChart(
            buckets: insights.spendingBuckets,
            selected: selectedBucket,
            onSelected: onBucketSelected,
            onOpenHistory: (bucket) => onOpenHistory(
              HistoryFilter(
                vehicleId: historyVehicleId,
                range: AnalyticsDateRange.custom(
                  start: bucket.startInclusive,
                  endInclusive: bucket.endExclusive.subtract(
                    const Duration(days: 1),
                  ),
                ),
              ),
            ),
          ),
          const _InsightSectionHeader(title: 'Spending breakdown'),
          _BreakdownPanel(
            items: insights.breakdown,
            totalSpendMinor: insights.totalSpendMinor,
            selected: selectedBreakdown,
            onSelected: onBreakdownSelected,
            onOpenHistory: (item) => onOpenHistory(
              HistoryFilter(
                vehicleId: historyVehicleId,
                type: item.type,
                range: range,
                categoryId: item.categoryId,
              ),
            ),
          ),
          const _InsightSectionHeader(title: 'Fuel insights'),
          _FuelPanel(
            insights: insights,
            onOpenFuelHistory: () => onOpenHistory(
              HistoryFilter(
                vehicleId: historyVehicleId,
                type: DailyActivityType.refuel,
                range: range,
              ),
            ),
          ),
          const _InsightSectionHeader(title: 'Mileage'),
          _MileagePanel(insights: insights),
          if (insights.hasIncome) ...[
            const _InsightSectionHeader(title: 'Income and net'),
            _IncomePanel(insights: insights),
          ],
        ],
      ],
    );
  }

  InsightAmountBucket? _selectedBucket() {
    if (insights.spendingBuckets.isEmpty) {
      return null;
    }
    final explicit = selectedBucketIndex;
    if (explicit != null &&
        explicit >= 0 &&
        explicit < insights.spendingBuckets.length) {
      return insights.spendingBuckets[explicit];
    }
    for (final bucket in insights.spendingBuckets.reversed) {
      if (bucket.totalSpendMinor > 0 || bucket.incomeMinor > 0) {
        return bucket;
      }
    }
    return insights.spendingBuckets.last;
  }

  InsightBreakdownItem? _selectedBreakdown() {
    if (insights.breakdown.isEmpty) {
      return null;
    }
    final key = selectedBreakdownKey;
    if (key != null) {
      for (final item in insights.breakdown) {
        if (item.key == key) {
          return item;
        }
      }
    }
    return insights.breakdown.first;
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.vehicles,
    required this.selectedVehicleId,
    required this.range,
    required this.onVehicleChanged,
    required this.onRangeChanged,
    required this.onCustomRangeRequested,
  });

  final List<Vehicle> vehicles;
  final String? selectedVehicleId;
  final AnalyticsDateRange range;
  final ValueChanged<String?> onVehicleChanged;
  final ValueChanged<AnalyticsDateRange> onRangeChanged;
  final VoidCallback onCustomRangeRequested;

  static const _allVehicles = '__all_vehicles__';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final safeSelectedVehicleId =
        vehicles.any((vehicle) => vehicle.id == selectedVehicleId)
        ? selectedVehicleId
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Insights',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: DTSpacing.md),
        DropdownButtonFormField<String>(
          key: const Key('insightsVehicleSelector'),
          initialValue: safeSelectedVehicleId ?? _allVehicles,
          isDense: true,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Vehicle',
            prefixIcon: const Icon(Icons.directions_car_rounded),
            filled: true,
            fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.34),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: DTSpacing.md,
              vertical: DTSpacing.md,
            ),
          ),
          items: [
            const DropdownMenuItem(
              value: _allVehicles,
              child: Text(
                'All vehicles',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final vehicle in vehicles)
              DropdownMenuItem(
                value: vehicle.id,
                child: Text(
                  vehicle.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            onVehicleChanged(value == _allVehicles ? null : value);
          },
        ),
        const SizedBox(height: DTSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _RangeChip(
                key: const Key('insightsRangeWeek'),
                label: 'Week',
                selected: range.preset == AnalyticsRangePreset.week,
                onSelected: () => onRangeChanged(AnalyticsDateRange.week),
              ),
              const SizedBox(width: DTSpacing.sm),
              _RangeChip(
                key: const Key('insightsRangeMonth'),
                label: 'Month',
                selected: range.preset == AnalyticsRangePreset.month,
                onSelected: () => onRangeChanged(AnalyticsDateRange.month),
              ),
              const SizedBox(width: DTSpacing.sm),
              _RangeChip(
                key: const Key('insightsRangeYear'),
                label: 'Year',
                selected: range.preset == AnalyticsRangePreset.year,
                onSelected: () => onRangeChanged(AnalyticsDateRange.year),
              ),
              const SizedBox(width: DTSpacing.sm),
              _RangeChip(
                key: const Key('insightsRangeAll'),
                label: 'All',
                selected: range.preset == AnalyticsRangePreset.all,
                onSelected: () => onRangeChanged(AnalyticsDateRange.all),
              ),
              const SizedBox(width: DTSpacing.sm),
              FilterChip(
                key: const Key('insightsCustomRangeButton'),
                selected: range.preset == AnalyticsRangePreset.custom,
                avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                label: Text(customAnalyticsRangeLabel(range)),
                onSelected: (_) => onCustomRangeRequested(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InsightSectionHeader extends StatelessWidget {
  const _InsightSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: DTSpacing.lg, bottom: DTSpacing.sm),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.insights});

  final VehicleInsights insights;

  @override
  Widget build(BuildContext context) {
    final metrics = <_MetricData>[
      _MetricData(
        key: const Key('insightsDistanceMetric'),
        label: 'Distance',
        value: _distanceValue(insights.distance),
        supporting: insights.distance.unavailableReason,
        icon: Icons.route_rounded,
      ),
      _MetricData(
        key: const Key('insightsFuelEconomyMetric'),
        label: 'Fuel economy',
        value: DTFormatters.ukMpg(insights.averageFuelEconomy.ukMpg),
        supporting: insights.averageFuelEconomy.unavailableReason,
        icon: Icons.local_gas_station_rounded,
      ),
      _MetricData(
        key: const Key('insightsCostPerDistanceMetric'),
        label: 'Running cost',
        value: _costPerDistance(
          insights.runningCostMinorPerDistance,
          insights.scope.distanceUnit,
        ),
        supporting: 'Usage-oriented spend per distance',
        icon: Icons.speed_rounded,
      ),
      if (insights.hasIncome)
        _MetricData(
          key: const Key('insightsIncomeMetric'),
          label: 'Income',
          value: DTFormatters.moneyMinor(insights.incomeMinor),
          supporting: 'Vehicle-related income',
          icon: Icons.trending_up_rounded,
        ),
      if (insights.hasIncome)
        _MetricData(
          key: const Key('insightsNetMetric'),
          label: 'Net',
          value: DTFormatters.moneyMinor(insights.netMinor),
          supporting: 'Income minus expenditure',
          icon: Icons.balance_rounded,
        ),
    ];

    return Column(
      children: [
        _PrimarySpendCard(insights: insights),
        const SizedBox(height: DTSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 340 ? 2 : 1;
            final width =
                (constraints.maxWidth - DTSpacing.md * (columns - 1)) / columns;
            return Wrap(
              spacing: DTSpacing.md,
              runSpacing: DTSpacing.md,
              children: [
                for (final metric in metrics)
                  SizedBox(
                    width: width,
                    child: _CompactMetricCard(data: metric),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  String _distanceValue(DistanceInsight distance) {
    final value = distance.value;
    final unit = distance.unit;
    if (value == null || unit == null) {
      return 'Unavailable';
    }
    return '${DTFormatters.wholeNumber(value)} ${unit.shortLabel}';
  }

  String _costPerDistance(double? minorPerDistance, DistanceUnit? unit) {
    if (minorPerDistance == null || unit == null) {
      return 'Unavailable';
    }
    return '${MoneyAmount.formatMinor(minorPerDistance.round())}/${unit.shortLabel}';
  }
}

class _PrimarySpendCard extends StatelessWidget {
  const _PrimarySpendCard({required this.insights});

  final VehicleInsights insights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DTInsightCard(
      key: const Key('insightsTotalSpendMetric'),
      emphasized: true,
      padding: const EdgeInsets.all(DTSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBadge(
                icon: Icons.account_balance_wallet_outlined,
                color: colors.primary,
              ),
              const SizedBox(width: DTSpacing.sm),
              Expanded(
                child: Text(
                  'Total spend',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DTSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              DTFormatters.moneyMinor(insights.totalSpendMinor),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: DTSpacing.md),
          Wrap(
            spacing: DTSpacing.sm,
            runSpacing: DTSpacing.sm,
            children: [
              _SpendPill(
                label: 'Fuel',
                value: DTFormatters.moneyMinor(insights.fuelSpendMinor),
                color: _insightAccent(context, 'fuel'),
              ),
              _SpendPill(
                label: 'Service',
                value: DTFormatters.moneyMinor(insights.serviceSpendMinor),
                color: _insightAccent(context, 'service'),
              ),
              _SpendPill(
                label: 'Other',
                value: DTFormatters.moneyMinor(insights.expenseSpendMinor),
                color: _insightAccent(context, 'expense'),
              ),
            ],
          ),
          if (insights.hasIncome) ...[
            const SizedBox(height: DTSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DTSpacing.md,
                vertical: DTSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.42),
                borderRadius: DTRadii.cardRadius,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Income ${DTFormatters.moneyMinor(insights.incomeMinor)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: DTSpacing.sm),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Net ${DTFormatters.moneyMinor(insights.netMinor)}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: _netColor(context, insights.netMinor),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SpendPill extends StatelessWidget {
  const _SpendPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DTSpacing.sm,
        vertical: DTSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: DTSpacing.xs),
          Flexible(
            child: Text(
              '$label $value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricData {
  const _MetricData({
    required this.key,
    required this.label,
    required this.value,
    required this.icon,
    this.supporting,
  });

  final Key key;
  final String label;
  final String value;
  final IconData icon;
  final String? supporting;
}

class _CompactMetricCard extends StatelessWidget {
  const _CompactMetricCard({required this.data});

  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DTInsightCard(
      key: data.key,
      padding: const EdgeInsets.all(DTSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBadge(icon: data.icon, color: colors.primary, small: true),
              const SizedBox(width: DTSpacing.sm),
              Expanded(
                child: Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DTSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              data.value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
          if (data.supporting != null) ...[
            const SizedBox(height: DTSpacing.xs),
            Text(
              data.supporting!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.icon,
    required this.color,
    this.small = false,
  });

  final IconData icon;
  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final size = small ? 28.0 : 34.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(small ? 9 : 11),
      ),
      child: Icon(icon, size: small ? 16 : 20, color: color),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        _IconBadge(icon: icon, color: color),
        const SizedBox(width: DTSpacing.sm),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: DTSpacing.sm),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactUnavailable extends StatelessWidget {
  const _CompactUnavailable({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: DTSpacing.md,
        vertical: DTSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.54),
        borderRadius: DTRadii.cardRadius,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: colors.onSurfaceVariant),
      ),
    );
  }
}

class _SpendingChart extends StatelessWidget {
  const _SpendingChart({
    required this.buckets,
    required this.selected,
    required this.onSelected,
    required this.onOpenHistory,
  });

  final List<InsightAmountBucket> buckets;
  final InsightAmountBucket? selected;
  final ValueChanged<int> onSelected;
  final ValueChanged<InsightAmountBucket> onOpenHistory;

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return const _InsightEmptyPanel(
        key: Key('insightsSpendingChartEmpty'),
        icon: Icons.bar_chart_rounded,
        title: 'No spending timeline yet',
        body: 'Spend and income buckets appear after records exist in this range.',
      );
    }
    final maxAmount = buckets
        .map((bucket) => bucket.totalSpendMinor)
        .fold<int>(0, mathMax);
    return DTInsightCard(
      key: const Key('insightsSpendingChart'),
      padding: const EdgeInsets.all(DTSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DTInsightBarChart(
            bars: [
              for (final bucket in buckets)
                DTInsightBarDatum(
                  index: bucket.index,
                  label: bucket.label,
                  value: bucket.totalSpendMinor,
                  valueLabel: DTFormatters.moneyMinor(bucket.totalSpendMinor),
                  semanticsLabel:
                      '${bucket.label}, ${DTFormatters.moneyMinor(bucket.totalSpendMinor)} spent',
                  color: _insightAccent(context, 'spend'),
                  selected: selected?.index == bucket.index,
                  onTap: () => onSelected(bucket.index),
                ),
            ],
            maxValue: maxAmount,
            barKeyPrefix: 'insightsSpendingBucket',
          ),
          const SizedBox(height: DTSpacing.md),
          if (selected != null) ...[
            Container(
              key: const Key('insightsSelectedSpendingBucket'),
              width: double.infinity,
              padding: const EdgeInsets.all(DTSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer
                    .withValues(alpha: 0.24),
                borderRadius: DTRadii.cardRadius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${selected!.label} · ${DTFormatters.moneyMinor(selected!.totalSpendMinor)} spent',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: DTSpacing.xs),
                  Text(
                    'Income ${DTFormatters.moneyMinor(selected!.incomeMinor)} / Net ${DTFormatters.moneyMinor(selected!.netMinor)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('insightsBucketDrilldownButton'),
                onPressed: () => onOpenHistory(selected!),
                icon: const Icon(Icons.manage_search_rounded),
                label: const Text('View records'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BreakdownPanel extends StatelessWidget {
  const _BreakdownPanel({
    required this.items,
    required this.totalSpendMinor,
    required this.selected,
    required this.onSelected,
    required this.onOpenHistory,
  });

  final List<InsightBreakdownItem> items;
  final int totalSpendMinor;
  final InsightBreakdownItem? selected;
  final ValueChanged<String> onSelected;
  final ValueChanged<InsightBreakdownItem> onOpenHistory;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _InsightEmptyPanel(
        key: Key('insightsBreakdownEmpty'),
        icon: Icons.donut_large_rounded,
        title: 'No spending breakdown',
        body: 'Only categories with real expenditure appear here.',
      );
    }
    final colors = Theme.of(context).colorScheme;
    final selectedVisual = selected == null
        ? null
        : _categoryVisual(context, selected!);
    return DTInsightCard(
      key: const Key('insightsBreakdown'),
      padding: const EdgeInsets.all(DTSpacing.md),
      child: Column(
        children: [
          for (final item in items) ...[
            _BreakdownRow(
              item: item,
              totalSpendMinor: totalSpendMinor,
              selected: selected?.key == item.key,
              onTap: () => onSelected(item.key),
            ),
            if (item != items.last) const SizedBox(height: DTSpacing.sm),
          ],
          if (selected != null) ...[
            const SizedBox(height: DTSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(DTSpacing.md),
              decoration: BoxDecoration(
                color: (selectedVisual?.color ?? colors.primary).withValues(
                  alpha: 0.11,
                ),
                borderRadius: DTRadii.cardRadius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${selected!.label} · ${DTFormatters.moneyMinor(selected!.amountMinor)}',
                    key: const Key('insightsSelectedBreakdown'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '${_percent(selected!.amountMinor, totalSpendMinor)} of expenditure',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const Key('insightsBreakdownDrilldownButton'),
                      onPressed: () => onOpenHistory(selected!),
                      icon: const Icon(Icons.manage_search_rounded),
                      label: const Text('View records'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _percent(int amount, int total) {
    if (total <= 0) {
      return '0%';
    }
    return '${(amount / total * 100).round()}%';
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.item,
    required this.totalSpendMinor,
    required this.selected,
    required this.onTap,
  });

  final InsightBreakdownItem item;
  final int totalSpendMinor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final visual = _categoryVisual(context, item);
    final ratio = totalSpendMinor <= 0
        ? 0.0
        : item.amountMinor / totalSpendMinor;
    final percent = totalSpendMinor <= 0 ? 0 : (ratio * 100).round();
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${item.label}, ${DTFormatters.moneyMinor(item.amountMinor)}, $percent percent',
      child: InkWell(
        key: Key('insightsBreakdown_${item.key}'),
        borderRadius: BorderRadius.circular(DTRadii.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(DTSpacing.sm),
          decoration: BoxDecoration(
            color: selected
                ? visual.color.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: DTRadii.cardRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _IconBadge(icon: visual.icon, color: visual.color),
                  const SizedBox(width: DTSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '$percent% of spend',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: DTSpacing.sm),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        DTFormatters.moneyMinor(item.amountMinor),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DTSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(DTRadii.card),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: ratio < 0
                      ? 0.0
                      : ratio > 1
                      ? 1.0
                      : ratio,
                  backgroundColor: colors.surfaceContainerHighest.withValues(
                    alpha: 0.72,
                  ),
                  color: visual.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FuelPanel extends StatelessWidget {
  const _FuelPanel({required this.insights, required this.onOpenFuelHistory});

  final VehicleInsights insights;
  final VoidCallback onOpenFuelHistory;

  @override
  Widget build(BuildContext context) {
    final economy = insights.averageFuelEconomy;
    if (!economy.isAvailable &&
        insights.averageFuelPriceMicrosPerLitre == null) {
      return _InsightEmptyPanel(
        key: const Key('insightsFuelUnavailable'),
        icon: Icons.local_gas_station_rounded,
        title: 'Fuel insights unavailable',
        body:
            economy.unavailableReason ??
            'Add valid refuels before fuel insight charts appear.',
      );
    }
    return Container(
      key: const Key('insightsFuelPanel'),
      padding: EdgeInsets.zero,
      decoration: const BoxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DTInsightCard(
            key: const Key('insightsFuelEconomyChart'),
            padding: const EdgeInsets.all(DTSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PanelTitle(
                  icon: Icons.speed_rounded,
                  title: 'Economy',
                  value: DTFormatters.ukMpg(economy.ukMpg),
                  color: _insightAccent(context, 'fuel'),
                ),
                const SizedBox(height: DTSpacing.sm),
                if (insights.fuelEconomyTrend.isEmpty)
                  _CompactUnavailable(
                    text:
                        economy.unavailableReason ??
                        'Add valid full-to-full refuels to see MPG.',
                  )
                else
                  DTInsightLineChart(
                    points: [
                      for (
                        var index = 0;
                        index < insights.fuelEconomyTrend.length;
                        index += 1
                      )
                        DTInsightLinePoint(
                          label: insights.fuelEconomyTrend[index].label,
                          value: insights.fuelEconomyTrend[index].ukMpg,
                          valueLabel:
                              '${insights.fuelEconomyTrend[index].ukMpg.toStringAsFixed(1)} MPG',
                          detailLabel:
                              '${insights.fuelEconomyTrend[index].label} · ${DTFormatters.wholeNumber(insights.fuelEconomyTrend[index].distance)} mi',
                          semanticsLabel:
                              '${insights.fuelEconomyTrend[index].label}, fuel economy ${insights.fuelEconomyTrend[index].ukMpg.toStringAsFixed(1)} UK MPG',
                        ),
                    ],
                    color: _insightAccent(context, 'fuel'),
                    pointKeyPrefix: 'insightsFuelEconomyPoint',
                    selectedDetailKey: const Key(
                      'insightsSelectedFuelEconomyPoint',
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: DTSpacing.md),
          DTInsightCard(
            key: const Key('insightsFuelPriceChart'),
            padding: const EdgeInsets.all(DTSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PanelTitle(
                  icon: Icons.local_gas_station_rounded,
                  title: 'Fuel price',
                  value: _fuelPriceCompact(
                    insights.averageFuelPriceMicrosPerLitre,
                  ),
                  color: _insightAccent(context, 'spend'),
                ),
                const SizedBox(height: DTSpacing.sm),
                if (insights.fuelPriceTrend.isEmpty)
                  const _CompactUnavailable(
                    text: 'Add fuel volume and cost to see price movement.',
                  )
                else
                  DTInsightLineChart(
                    points: [
                      for (
                        var index = 0;
                        index < insights.fuelPriceTrend.length;
                        index += 1
                      )
                        DTInsightLinePoint(
                          label: insights.fuelPriceTrend[index].label,
                          value:
                              insights.fuelPriceTrend[index].microsPerLitre /
                              FuelNumbers.microsPerPence,
                          valueLabel: _fuelPriceCompact(
                            insights.fuelPriceTrend[index].microsPerLitre,
                          ),
                          detailLabel: insights.fuelPriceTrend[index].label,
                          semanticsLabel:
                              '${insights.fuelPriceTrend[index].label}, fuel price ${_fuelPriceCompact(insights.fuelPriceTrend[index].microsPerLitre)}',
                        ),
                    ],
                    color: _insightAccent(context, 'spend'),
                    pointKeyPrefix: 'insightsFuelPricePoint',
                    selectedDetailKey: const Key(
                      'insightsSelectedFuelPricePoint',
                    ),
                  ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('insightsFuelDrilldownButton'),
              onPressed: onOpenFuelHistory,
              icon: const Icon(Icons.manage_search_rounded),
              label: const Text('View fuel'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MileagePanel extends StatelessWidget {
  const _MileagePanel({required this.insights});

  final VehicleInsights insights;

  @override
  Widget build(BuildContext context) {
    final unit = insights.scope.distanceUnit;
    if (insights.scope.isAllVehicles) {
      return const _InsightEmptyPanel(
        key: Key('insightsMileageUnavailable'),
        icon: Icons.route_rounded,
        title: 'Select one vehicle',
        body: 'Odometer trends are vehicle-specific and are not combined across vehicles.',
      );
    }
    if (unit == null || insights.odometerTrend.isEmpty) {
      return const _InsightEmptyPanel(
        key: Key('insightsMileageUnavailable'),
        icon: Icons.route_rounded,
        title: 'Mileage trend unavailable',
        body: 'At least two valid readings in the range are needed.',
      );
    }
    return DTInsightCard(
      key: const Key('insightsMileagePanel'),
      padding: const EdgeInsets.all(DTSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(
            icon: Icons.route_rounded,
            title: 'Odometer trend',
            value: DTFormatters.odometer(
              insights.odometerTrend.last.odometer,
              unit,
            ),
            color: _insightAccent(context, 'mileage'),
          ),
          const SizedBox(height: DTSpacing.sm),
          DTInsightLineChart(
            points: [
              for (
                var index = 0;
                index < insights.odometerTrend.length;
                index += 1
              )
                DTInsightLinePoint(
                  label: insights.odometerTrend[index].label,
                  value: insights.odometerTrend[index].odometer.toDouble(),
                  valueLabel: DTFormatters.odometer(
                    insights.odometerTrend[index].odometer,
                    unit,
                  ),
                  detailLabel: DTFormatters.dateTime(
                    insights.odometerTrend[index].date,
                  ),
                  semanticsLabel:
                      '${insights.odometerTrend[index].label}, odometer ${DTFormatters.odometer(insights.odometerTrend[index].odometer, unit)}',
                ),
            ],
            color: _insightAccent(context, 'mileage'),
            pointKeyPrefix: 'insightsMileagePoint',
            selectedDetailKey: const Key('insightsSelectedMileagePoint'),
          ),
        ],
      ),
    );
  }
}

class _IncomePanel extends StatelessWidget {
  const _IncomePanel({required this.insights});

  final VehicleInsights insights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final maxAmount = insights.incomeMinor > insights.totalSpendMinor
        ? insights.incomeMinor
        : insights.totalSpendMinor;
    return DTInsightCard(
      key: const Key('insightsIncomePanel'),
      padding: const EdgeInsets.all(DTSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Net result',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    DTFormatters.moneyMinor(insights.netMinor),
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: _netColor(context, insights.netMinor),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DTSpacing.md),
          _IncomeBar(
            label: 'Income',
            value: DTFormatters.moneyMinor(insights.incomeMinor),
            amount: insights.incomeMinor,
            maxAmount: maxAmount,
            color: _insightAccent(context, 'income'),
          ),
          const SizedBox(height: DTSpacing.sm),
          _IncomeBar(
            label: 'Expenditure',
            value: DTFormatters.moneyMinor(insights.totalSpendMinor),
            amount: insights.totalSpendMinor,
            maxAmount: maxAmount,
            color: _insightAccent(context, 'spend'),
          ),
        ],
      ),
    );
  }
}

class _IncomeBar extends StatelessWidget {
  const _IncomeBar({
    required this.label,
    required this.value,
    required this.amount,
    required this.maxAmount,
    required this.color,
  });

  final String label;
  final String value;
  final int amount;
  final int maxAmount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = maxAmount <= 0 ? 0.0 : (amount / maxAmount).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  value,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: DTSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(DTRadii.card),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: ratio,
            color: color,
            backgroundColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.72),
          ),
        ),
      ],
    );
  }
}

class _InsightEmptyPanel extends StatelessWidget {
  const _InsightEmptyPanel({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(DTSpacing.lg),
      decoration: _panelDecoration(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: DTSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: DTSpacing.xs),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => onSelected(),
    );
  }
}

class _CategoryVisual {
  const _CategoryVisual({required this.icon, required this.color});

  final IconData icon;
  final Color color;
}

_CategoryVisual _categoryVisual(
  BuildContext context,
  InsightBreakdownItem item,
) {
  if (item.type == DailyActivityType.refuel) {
    return _CategoryVisual(
      icon: Icons.local_gas_station_rounded,
      color: _insightAccent(context, 'fuel'),
    );
  }
  if (item.type == DailyActivityType.service) {
    return _CategoryVisual(
      icon: Icons.build_circle_outlined,
      color: _insightAccent(context, 'service'),
    );
  }

  final categoryKey = item.categoryId ?? item.key;
  return switch (categoryKey) {
    'cat_expense_parking' => _CategoryVisual(
      icon: Icons.local_parking_rounded,
      color: _insightAccent(context, 'parking'),
    ),
    'cat_expense_toll' => _CategoryVisual(
      icon: Icons.toll_rounded,
      color: _insightAccent(context, 'toll'),
    ),
    'cat_expense_repair' || 'cat_expense_parts' => _CategoryVisual(
      icon: Icons.handyman_rounded,
      color: _insightAccent(context, 'repair'),
    ),
    'cat_expense_cleaning' => _CategoryVisual(
      icon: Icons.cleaning_services_rounded,
      color: _insightAccent(context, 'cleaning'),
    ),
    'cat_expense_insurance' => _CategoryVisual(
      icon: Icons.verified_user_outlined,
      color: _insightAccent(context, 'insurance'),
    ),
    'cat_expense_tax' || 'cat_expense_mot' => _CategoryVisual(
      icon: Icons.assignment_outlined,
      color: _insightAccent(context, 'ownership'),
    ),
    _ => _CategoryVisual(
      icon: Icons.receipt_long_rounded,
      color: _hashedAccent(context, categoryKey),
    ),
  };
}

Color _insightAccent(BuildContext context, String key) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (key) {
    'fuel' => dark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E),
    'service' => dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
    'expense' => dark ? const Color(0xFFA7F3D0) : const Color(0xFF047857),
    'income' => dark ? const Color(0xFF86EFAC) : const Color(0xFF15803D),
    'spend' => dark ? const Color(0xFF93C5FD) : const Color(0xFF2563EB),
    'mileage' => dark ? const Color(0xFFC4B5FD) : const Color(0xFF6D28D9),
    'parking' => dark ? const Color(0xFF7DD3FC) : const Color(0xFF0369A1),
    'toll' => dark ? const Color(0xFFFDA4AF) : const Color(0xFFE11D48),
    'repair' => dark ? const Color(0xFFFCD34D) : const Color(0xFFD97706),
    'cleaning' => dark ? const Color(0xFF67E8F9) : const Color(0xFF0891B2),
    'insurance' => dark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
    'ownership' => dark ? const Color(0xFFF0ABFC) : const Color(0xFFC026D3),
    _ => Theme.of(context).colorScheme.primary,
  };
}

Color _hashedAccent(BuildContext context, String key) {
  final palette = [
    _insightAccent(context, 'parking'),
    _insightAccent(context, 'toll'),
    _insightAccent(context, 'repair'),
    _insightAccent(context, 'cleaning'),
    _insightAccent(context, 'ownership'),
  ];
  final index = (key.hashCode & 0x7fffffff) % palette.length;
  return palette[index];
}

Color _netColor(BuildContext context, int netMinor) {
  final colors = Theme.of(context).colorScheme;
  if (netMinor > 0) {
    return _insightAccent(context, 'income');
  }
  if (netMinor < 0) {
    return colors.error.withValues(alpha: 0.84);
  }
  return colors.onSurfaceVariant;
}

String _fuelPriceCompact(int? microsPerLitre) {
  if (microsPerLitre == null) {
    return '-';
  }
  final pence = microsPerLitre / FuelNumbers.microsPerPence;
  return '${pence.toStringAsFixed(1)} p/L';
}

BoxDecoration _panelDecoration(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
    borderRadius: DTRadii.cardRadius,
    border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.55)),
  );
}

int mathMax(int a, int b) => a > b ? a : b;
