import '../../../app/router/app_navigation.dart';
import 'insight_components.dart';
import 'insight_formatters.dart';
import '../../../app/theme/dt_motion.dart';
import '../domain/vehicle_insights.dart';
import 'insight_visuals.dart';

import 'package:flutter/material.dart';

import '../../daily_records/domain/income_activity.dart';
import '../../daily_records/domain/income_earnings.dart';
import '../../daily_records/presentation/earnings_formatters.dart';
import '../../vehicles/domain/vehicle.dart';

class IncomeActivityEarningsPanel extends StatefulWidget {
  const IncomeActivityEarningsPanel({
    super.key,
    required this.records,
    this.unit,
    this.buckets = const [],
    this.onOpenHistory,
    this.initialFilter = 'driving',
    this.onFilterChanged,
    this.initialDisplayUnit = DistanceUnit.miles,
    this.onDisplayUnitChanged,
    this.vehicleNames = const {},
  });
  final List<IncomeEarnings> records;
  final DistanceUnit? unit;
  final String initialFilter;
  final ValueChanged<String>? onFilterChanged;
  final DistanceUnit initialDisplayUnit;
  final ValueChanged<DistanceUnit>? onDisplayUnitChanged;
  final Map<String, String> vehicleNames;
  final List<InsightAmountBucket> buckets;
  final void Function(Set<IncomeActivityType>, InsightAmountBucket?)?
  onOpenHistory;
  @override
  State<IncomeActivityEarningsPanel> createState() =>
      _IncomeActivityEarningsPanelState();
}

class _IncomeActivityEarningsPanelState
    extends State<IncomeActivityEarningsPanel> {
  late String _filter = widget.initialFilter;
  late DistanceUnit _allUnit = widget.initialDisplayUnit;
  @override
  Widget build(BuildContext context) {
    final selected = widget.records.where(
      (r) =>
          _filter == 'all' ||
          (_filter == 'driving'
              ? [
                  IncomeActivityType.rideshare,
                  IncomeActivityType.delivery,
                ].contains(r.activity.type)
              : r.activity.type.name == _filter),
    );
    final s = EarningsSummary(selected);
    final types = _filter == 'all'
        ? IncomeActivityType.values.toSet()
        : _filter == 'driving'
        ? {IncomeActivityType.rideshare, IncomeActivityType.delivery}
        : {IncomeActivityType.values.byName(_filter)};
    final explicit = s.records
        .where(
          (r) => [
            r.activity.baseMinor,
            r.activity.tipsMinor,
            r.activity.travelMinor,
            r.activity.otherMinor,
          ].every((v) => v != null),
        )
        .toList();
    final totals = List<int>.filled(widget.buckets.length, 0);
    final counts = List<int>.filled(widget.buckets.length, 0);
    for (final r in s.records) {
      var low = 0, high = widget.buckets.length - 1;
      while (low <= high) {
        final mid = (low + high) ~/ 2;
        final b = widget.buckets[mid];
        if (r.income.eventDateTime.isBefore(b.startInclusive)) {
          high = mid - 1;
        } else if (!r.income.eventDateTime.isBefore(b.endExclusive)) {
          low = mid + 1;
        } else {
          totals[mid] += r.income.amountMinor;
          counts[mid]++;
          break;
        }
      }
    }
    final unit = widget.unit ?? _allUnit;
    final money = earningsMoney;
    final composition = <(String, int, InsightTone)>[
      if (explicit.isNotEmpty) ...[
        (
          'Base',
          explicit.fold<int>(0, (v, r) => v + r.activity.baseMinor!),
          InsightTone.teal,
        ),
        (
          'Tips',
          explicit.fold<int>(0, (v, r) => v + r.activity.tipsMinor!),
          InsightTone.warm,
        ),
        (
          'Travel compensation',
          explicit.fold<int>(0, (v, r) => v + r.activity.travelMinor!),
          InsightTone.mint,
        ),
        (
          'Other income',
          explicit.fold<int>(0, (v, r) => v + r.activity.otherMinor!),
          InsightTone.neutral,
        ),
      ],
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final activityGroups = [
      for (final type in IncomeActivityType.values)
        (
          type,
          EarningsSummary(s.records.where((r) => r.activity.type == type)),
        ),
    ]..sort((a, b) => b.$2.grossMinor.compareTo(a.$2.grossMinor));
    String date(DateTime at) => InsightFormat.date(at);
    return Column(
      key: const Key('incomeActivityEarningsPanel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: const Key('earningsActivityFilter'),
          initialValue: _filter,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Activity filter',
            prefixIcon: Icon(Icons.filter_list),
          ),
          items: [
            const DropdownMenuItem(
              value: 'driving',
              child: Text('Rideshare + delivery'),
            ),
            const DropdownMenuItem(
              value: 'all',
              child: Text('All income types'),
            ),
            for (final type in IncomeActivityType.values)
              DropdownMenuItem(value: type.name, child: Text(type.label)),
          ],
          onChanged: (v) {
            setState(() => _filter = v!);
            widget.onFilterChanged?.call(v!);
          },
        ),
        if (widget.unit == null) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<DistanceUnit>(
            initialValue: _allUnit,
            decoration: const InputDecoration(
              labelText: 'Display distance unit (all vehicles)',
            ),
            items: [
              for (final u in DistanceUnit.values)
                DropdownMenuItem(value: u, child: Text(u.label)),
            ],
            onChanged: (v) {
              setState(() => _allUnit = v!);
              widget.onDisplayUnitChanged?.call(v!);
            },
          ),
        ],
        const SizedBox(height: 20),
        InsightMetricTile(
          key: const Key('earningsGrossHero'),
          label: _filter == 'driving'
              ? 'Driving-activity gross'
              : 'Gross received',
          value: money(s.grossMinor),
          icon: Icons.trending_up,
          tone: InsightTone.teal,
          hero: true,
          caption: '${s.count} recorded activities',
        ),
        const SizedBox(height: 12),
        InsightMetricGrid(
          key: const Key('earningsMetricGrid'),
          alignRows: true,
          tiles: [
            InsightMetricTile(
              key: const Key('earningsGrossMetric'),
              label: 'Gross',
              value: money(s.grossMinor),
              icon: Icons.trending_up,
              tone: InsightTone.teal,
            ),
            InsightMetricTile(
              key: const Key('earningsLinkedMetric'),
              label: 'Linked direct costs',
              value: money(s.recordedCostsMinor),
              icon: Icons.link,
              tone: InsightTone.warm,
            ),
            InsightMetricTile(
              key: const Key('earningsNetMetric'),
              label: 'Net after linked direct costs',
              value: s.netMinor == null ? 'Not available' : money(s.netMinor),
              icon: Icons.account_balance_wallet_outlined,
              tone: s.netMinor == null
                  ? InsightTone.neutral
                  : s.netMinor! < 0
                  ? InsightTone.rose
                  : InsightTone.teal,
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Linked costs only.'),
        Text(
          'Direct costs are complete for ${s.completeCount} of ${s.count} activities.',
        ),
        if (s.netMinor == null && s.count > 0)
          const Text('Complete the linked-cost review to show net.'),
        if (s.count == 0)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No income activities match this filter. Simple historical income remains under All income types.',
            ),
          )
        else ...[
          if (s.perDistance(unit) != null ||
              s.perHour() != null ||
              s.perDelivery != null) ...[
            const InsightSectionTitle('Average rates'),
            InsightMetricGrid(
              tiles: [
                if (s.perDistance(unit) != null)
                  InsightMetricTile(
                    key: const Key('earningsDistanceRate'),
                    label:
                        'Per ${unit == DistanceUnit.miles ? 'mile' : 'kilometre'}',
                    value: '${money(s.perDistance(unit))} / ${unit.shortLabel}',
                    icon: Icons.route_outlined,
                    caption:
                        '${s.distanceCount} of ${s.count} activities${s.netMinor == null ? '' : ' · Net ${money(s.perDistance(unit, net: true))} / ${unit.shortLabel}'}',
                  ),
                if (s.perHour() != null)
                  InsightMetricTile(
                    key: const Key('earningsHourlyRate'),
                    label: 'Per hour',
                    value: '${money(s.perHour())} / hour',
                    icon: Icons.schedule_outlined,
                    tone: InsightTone.warm,
                    caption:
                        '${s.durationCount} of ${s.count} activities${s.netMinor == null ? '' : ' · Net ${money(s.perHour(net: true))} / hour'}',
                  ),
                if (s.perDelivery != null)
                  InsightMetricTile(
                    key: const Key('earningsDeliveryRate'),
                    label: 'Per delivery',
                    value: '${money(s.perDelivery)} / delivery',
                    icon: Icons.local_shipping_outlined,
                    tone: InsightTone.neutral,
                    caption: '${s.deliveryCount} of ${s.count} activities',
                  ),
              ],
            ),
          ],
          if (widget.buckets.isNotEmpty) ...[
            InsightSectionTitle(
              _filter == 'driving'
                  ? 'Driving earnings · gross GBP'
                  : 'Selected income · gross GBP',
            ),
            DTInsightCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (counts.where((c) => c > 0).length == 1)
                    const Text(
                      'One recorded period; not enough data to describe a trend.',
                    )
                  else
                    DTInsightBarChart(
                      bars: [
                        for (var j = 0; j < widget.buckets.length; j++)
                          DTInsightBarDatum(
                            index: j,
                            label: widget.buckets[j].label,
                            value: totals[j],
                            valueLabel: money(totals[j]),
                            semanticsLabel:
                                '${widget.buckets[j].label}: ${money(totals[j])} gross, ${counts[j]} activities',
                            color: Theme.of(context).colorScheme.primary,
                            selected: false,
                            onTap: () => widget.onOpenHistory?.call(
                              types,
                              widget.buckets[j],
                            ),
                          ),
                      ],
                      maxValue: totals.fold<int>(0, (a, b) => a > b ? a : b),
                      barKeyPrefix: 'earningsBucket',
                    ),
                  ExpansionTile(
                    key: const PageStorageKey('earningsPeriodTotals'),
                    tilePadding: EdgeInsets.zero,
                    expansionAnimationStyle: DTMotion.reduceMotionOf(context)
                        ? AnimationStyle.noAnimation
                        : null,
                    title: const Text('Period totals'),
                    children: [
                      for (var j = 0; j < widget.buckets.length; j++)
                        ListTile(
                          title: Text(widget.buckets[j].label),
                          subtitle: Text(
                            '${money(totals[j])} gross · ${counts[j]} activities',
                          ),
                          onTap: () => widget.onOpenHistory?.call(
                            types,
                            widget.buckets[j],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const InsightSectionTitle('Earnings breakdown'),
          if (explicit.isEmpty)
            const Text(
              'No explicit breakdown recorded. Missing components remain unknown.',
            )
          else ...[
            Text(
              '${explicit.length} of ${s.count} records include a breakdown.',
            ),
            for (final row in composition)
              InsightRankedRow(
                label: row.$1,
                value: money(row.$2),
                fraction: composition.first.$2 == 0
                    ? 0
                    : row.$2 / composition.first.$2,
                tone: row.$3,
              ),
          ],
          const InsightSectionTitle('Income by activity type'),
          for (final group in activityGroups)
            if (group.$2.count > 0)
              InsightRankedRow(
                label: group.$1.label,
                value: money(group.$2.grossMinor),
                fraction: activityGroups.first.$2.grossMinor == 0
                    ? 0
                    : group.$2.grossMinor / activityGroups.first.$2.grossMinor,
                share: '${group.$2.count} activities',
                tone: group.$1 == IncomeActivityType.delivery
                    ? InsightTone.warm
                    : InsightTone.teal,
              ),
          InsightSectionTitle(
            'Recent activities',
            action: 'View all',
            onAction: widget.onOpenHistory == null
                ? null
                : () => widget.onOpenHistory!(types, null),
          ),
          for (final r in s.records.reversed.take(3))
            ListTile(
              visualDensity: VisualDensity.compact,
              minTileHeight: 64,
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${date(r.income.eventDateTime)} · ${money(r.income.amountMinor)}',
              ),
              subtitle: Text(
                [
                  r.activity.type.label,
                  if (widget.unit == null)
                    widget.vehicleNames[r.income.vehicleId] ?? 'Vehicle',
                  if (r.activity.durationMinutes != null)
                    '${r.activity.durationMinutes} min',
                  if (r.activity.distanceMm != null)
                    '${InsightFormat.distance(ActivityDistance.value(r.activity.distanceMm!, unit))} ${unit.shortLabel}',
                  if (r.activity.deliveryCount != null)
                    '${r.activity.deliveryCount} deliveries',
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => AppNavigation.openIncome(context, income: r.income),
            ),
        ],
        TextButton.icon(
          onPressed: () => showInsightInformation(
            context,
            'Earnings definitions',
            'Net after linked direct costs is not profit. No fuel, maintenance or acquisition costs are allocated automatically. Rates use only activities with the matching denominator. Work/Salary describes associated work income. Linked expenses count once in expenditure. Activity costs follow the income date for this analysis.',
          ),
          icon: const Icon(Icons.info_outline, size: 18),
          label: const Text('How earnings are calculated'),
        ),
      ],
    );
  }
}
