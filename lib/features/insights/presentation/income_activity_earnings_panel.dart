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
  });
  final List<IncomeEarnings> records;
  final DistanceUnit? unit;
  @override
  State<IncomeActivityEarningsPanel> createState() =>
      _IncomeActivityEarningsPanelState();
}

class _IncomeActivityEarningsPanelState
    extends State<IncomeActivityEarningsPanel> {
  String _filter = 'driving';
  DistanceUnit _allUnit = DistanceUnit.miles;
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
    final unit = widget.unit ?? _allUnit;
    Widget row(String title, String value) => ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(value),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          key: const Key('incomeActivityEarningsPanel'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Income activities & earnings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            DropdownButtonFormField<String>(
              initialValue: _filter,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Activity filter'),
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
              onChanged: (v) => setState(() => _filter = v!),
            ),
            if (widget.unit == null)
              DropdownButtonFormField<DistanceUnit>(
                initialValue: _allUnit,
                decoration: const InputDecoration(
                  labelText: 'Display distance unit (all vehicles)',
                ),
                items: [
                  for (final u in DistanceUnit.values)
                    DropdownMenuItem(value: u, child: Text(u.label)),
                ],
                onChanged: (v) => setState(() => _allUnit = v!),
              ),
            if (s.count == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No income activities match this filter. Simple historical income remains under All income types.',
                ),
              )
            else ...[
              row('Gross received', earningsMoney(s.grossMinor)),
              row('Recorded direct costs', earningsMoney(s.recordedCostsMinor)),
              row('Net after direct costs', earningsMoney(s.netMinor)),
              Text(
                '${s.completeCount} of ${s.count} activities have complete direct costs. Costs are not allocated from refuels or services.',
              ),
              row(
                'Gross per ${unit.shortLabel}',
                earningsMoney(s.perDistance(unit)),
              ),
              row(
                'Net per ${unit.shortLabel}',
                earningsMoney(s.perDistance(unit, net: true)),
              ),
              Text(
                '${s.distanceCount} of ${s.count} activities include distance; ${s.netDistanceCount} also have complete costs.',
              ),
              row('Gross per hour', earningsMoney(s.perHour())),
              row('Net per hour', earningsMoney(s.perHour(net: true))),
              Text(
                '${s.durationCount} of ${s.count} activities include duration; ${s.netDurationCount} also have complete costs.',
              ),
              if (s.deliveryCount > 0) ...[
                row('Income per delivery', earningsMoney(s.perDelivery)),
                Text(
                  '${s.deliveryCount} of ${s.count} activities include delivery count.',
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                'Rates use only entries with the matching denominator. Work/Salary describes associated work income, not vehicle-generated profit. Linked expenses are already counted once in ordinary expenditure. Activity costs follow the income date for this analysis.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
