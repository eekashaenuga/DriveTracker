import 'insight_components.dart';
import 'insight_formatters.dart';
import 'insights_detail_screen.dart';
import '../../../app/theme/dt_motion.dart';
import '../../vehicles/domain/vehicle.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../core/calculations/analytics_date_range.dart';
import '../../../core/utilities/formatters.dart';
import '../../../shared/widgets/analytics_date_range_picker.dart';
import '../../../shared/widgets/dt_empty_state.dart';
import '../../daily_records/domain/income_activity.dart';
import '../../daily_records/domain/income_earnings.dart';
import '../domain/vehicle_insights.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});
  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  String? _vehicleId, _signature;
  bool _initialized = false;
  String _activityFilter = 'driving';
  DistanceUnit _earningsUnit = DistanceUnit.miles;
  var _range = AnalyticsDateRange.month;
  Future<VehicleInsights>? _future;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriveTrackerController>();
    final vehicles = c.activeVehicles;
    if (!_initialized) {
      _initialized = true;
      _vehicleId = c.selectedVehicle?.id;
    }
    if (_vehicleId != null && !vehicles.any((v) => v.id == _vehicleId)) {
      _vehicleId = null;
    }
    if (vehicles.isEmpty) {
      return const Scaffold(
        body: SafeArea(
          child: DTEmptyState(
            icon: Icons.insights_outlined,
            title: 'No active vehicles',
            body: 'Add or restore a vehicle before reviewing Insights.',
          ),
        ),
      );
    }
    final signature =
        '${c.dataRevision}|$_vehicleId|${_range.preset.name}|${_range.customStart?.toIso8601String()}|${_range.customEndInclusive?.toIso8601String()}';
    if (_future == null || _signature != signature) {
      _signature = signature;
      _future = c.insightsFor(vehicleId: _vehicleId, range: _range);
    }
    final presets = <(String, AnalyticsRangePreset)>[
      ('This month', AnalyticsRangePreset.month),
      ('Last month', AnalyticsRangePreset.lastMonth),
      ('Last 3 months', AnalyticsRangePreset.lastThreeMonths),
      ('This year', AnalyticsRangePreset.year),
      ('All time', AnalyticsRangePreset.all),
    ];
    return Scaffold(
      body: SafeArea(
        child: ListView(
          key: const Key('insightsScreenList'),
          padding: const EdgeInsets.all(16),
          children: [
            Text('Insights', style: Theme.of(context).textTheme.headlineMedium),
            const Text('Based on recorded data'),
            const SizedBox(height: 16),
            KeyedSubtree(
              key: ValueKey(_vehicleId),
              child: DropdownButtonFormField<String>(
                key: const Key('insightsVehicleSelector'),
                initialValue: _vehicleId ?? '__all__',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Vehicle',
                  prefixIcon: Icon(Icons.directions_car_outlined),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '__all__',
                    child: Text('All active vehicles'),
                  ),
                  for (final v in vehicles)
                    DropdownMenuItem(
                      value: v.id,
                      child: Text(v.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) =>
                    setState(() => _vehicleId = v == '__all__' ? null : v),
              ),
            ),
            Wrap(
              children: [
                for (final (label, preset) in presets)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      showCheckmark: false,
                      selected: _range.preset == preset,
                      onSelected: (_) => setState(
                        () => _range = AnalyticsDateRange.preset(preset),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ActionChip(
                    key: const Key('insightsCustomRangeButton'),
                    label: Text(InsightFormat.customRange(_range)),
                    onPressed: () async {
                      final range = await pickAnalyticsDateRange(
                        context: context,
                        currentRange: _range,
                        currentDate: c.currentTime,
                        pickerKey: const Key('insightsCustomRangePicker'),
                        helpText: 'Select insights range',
                      );
                      if (mounted && range != null) {
                        setState(() => _range = range);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<VehicleInsights>(
              key: ValueKey(signature),
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      const DTEmptyState(
                        icon: Icons.error_outline,
                        title: 'Could not load Insights',
                        body: 'Your records are unchanged. Try loading again.',
                      ),
                      TextButton(
                        key: const Key('insightsRetry'),
                        onPressed: () => setState(() => _signature = null),
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
                        key: Key('insightsLoading'),
                      ),
                    ),
                  );
                }
                return _InsightsContents(
                  insights: snapshot.data!,
                  range: _range,
                  activityFilter: _activityFilter,
                  earningsUnit: _earningsUnit,
                  onActivityFilterChanged: (v) =>
                      setState(() => _activityFilter = v),
                  onEarningsUnitChanged: (v) =>
                      setState(() => _earningsUnit = v),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightsContents extends StatefulWidget {
  const _InsightsContents({
    required this.insights,
    required this.range,
    required this.activityFilter,
    required this.earningsUnit,
    required this.onActivityFilterChanged,
    required this.onEarningsUnitChanged,
  });
  final VehicleInsights insights;
  final AnalyticsDateRange range;
  final String activityFilter;
  final DistanceUnit earningsUnit;
  final ValueChanged<String> onActivityFilterChanged;
  final ValueChanged<DistanceUnit> onEarningsUnitChanged;
  @override
  State<_InsightsContents> createState() => _InsightsContentsState();
}

class _InsightsContentsState extends State<_InsightsContents> {
  Future<void> open(InsightDetailKind kind) async {
    final page = InsightsDetailScreen(
      kind: kind,
      insights: widget.insights,
      range: widget.range,
      activityFilter: widget.activityFilter,
      earningsUnit: widget.earningsUnit,
      onActivityFilterChanged: widget.onActivityFilterChanged,
      onEarningsUnitChanged: widget.onEarningsUnitChanged,
    );
    final route = DTMotion.reduceMotionOf(context)
        ? PageRouteBuilder<void>(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => page,
          )
        : MaterialPageRoute<void>(builder: (_) => page);
    await Navigator.of(context).push(route);
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.insights;
    final driving = EarningsSummary(
      i.incomeActivities.where(
        (r) => const {
          IncomeActivityType.rideshare,
          IncomeActivityType.delivery,
        }.contains(r.activity.type),
      ),
    );
    final period = insightPeriodLabel(widget.range);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsightMetricGrid(
          maxColumns: 2,
          tiles: [
            InsightMetricTile(
              key: const Key('insightsTotalSpendMetric'),
              label: 'Recorded operating spend',
              value: DTFormatters.moneyMinor(i.totalSpendMinor),
              icon: Icons.account_balance_wallet_outlined,
              caption: period,
              hero: true,
            ),
            InsightMetricTile(
              key: const Key('insightsDrivingGrossMetric'),
              label: 'Driving-activity gross',
              value: DTFormatters.moneyMinor(driving.grossMinor),
              icon: Icons.trending_up,
              tone: InsightTone.warm,
              caption: driving.count == 0
                  ? 'No driving activities · $period'
                  : '$period · ${driving.count} activities',
              hero: true,
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (!i.hasAnyData)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text('No records in this range'),
          ),
        InsightNavigationCard(
          key: const Key('insightsCostsSection'),
          title: 'Costs',
          value: DTFormatters.moneyMinor(i.totalSpendMinor),
          period: period,
          summary: 'Fuel, service & expenses',
          icon: Icons.payments_outlined,
          onTap: () => open(InsightDetailKind.costs),
        ),
        InsightNavigationCard(
          key: const Key('insightsFuelSection'),
          title: 'Fuel',
          value: DTFormatters.moneyMinor(i.fuelSpendMinor),
          period: period,
          summary: [
            if (i.averageFuelPriceMicrosPerLitre != null)
              InsightFormat.price(i.averageFuelPriceMicrosPerLitre),
            if (i.averageFuelEconomy.ukMpg != null)
              InsightFormat.economy(i.averageFuelEconomy.ukMpg),
            if (i.refuelCount == 0) 'No fills recorded',
          ].join(' · '),
          icon: Icons.local_gas_station_outlined,
          tone: InsightTone.warm,
          onTap: () => open(InsightDetailKind.fuel),
        ),
        InsightNavigationCard(
          key: const Key('insightsEarningsSection'),
          title: 'Earnings',
          value: DTFormatters.moneyMinor(driving.grossMinor),
          period: period,
          summary:
              '${driving.count} driving activities · ${i.incomeActivities.length} income records',
          icon: Icons.trending_up,
          tone: InsightTone.rose,
          onTap: () => open(InsightDetailKind.earnings),
        ),
      ],
    );
  }
}
