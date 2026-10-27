import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../core/utilities/formatters.dart';
import '../../vehicles/domain/vehicle.dart';
import '../domain/income.dart';
import '../domain/income_activity.dart';
import '../domain/income_earnings.dart';
import 'earnings_formatters.dart';

class IncomeEarningsDetails extends StatelessWidget {
  const IncomeEarningsDetails({
    super.key,
    required this.income,
    required this.unit,
  });
  final Income income;
  final DistanceUnit unit;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriveTrackerController>();
    return FutureBuilder<IncomeEarnings>(
      future: c.incomeEarnings(income),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Could not load activity costs. Reopen to retry.');
        }
        final e = snapshot.data;
        if (e == null) return const LinearProgressIndicator();
        final a = income.activity;
        Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                child: Column(children: children),
              ),
            ],
          ),
        );
        Widget row(String name, String value) =>
            ListTile(title: Text(name), subtitle: Text(value));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            section('Earnings', [
              row('Gross received', earningsMoney(income.amountMinor)),
              if (a.hasBreakdown) ...[
                row('Base / pay', earningsMoney(a.baseMinor)),
                row('Tips', earningsMoney(a.tipsMinor)),
                row('Travel compensation', earningsMoney(a.travelMinor)),
                row('Other income', earningsMoney(a.otherMinor)),
              ],
            ]),
            section('Activity', [
              row('Template', a.type.label),
              if (a.distanceMm != null)
                row(
                  a.type == IncomeActivityType.reimbursement
                      ? 'Distance claimed'
                      : 'Activity distance',
                  '${ActivityDistance.input(a.distanceMm, unit)} ${unit.shortLabel}',
                ),
              if (a.durationMinutes != null)
                row('Duration', '${a.durationMinutes} minutes'),
              if (a.deliveryCount != null)
                row('Deliveries', '${a.deliveryCount}'),
              if (a.rateMicros != null)
                row(
                  'Contractual reimbursement rate',
                  '£${(a.rateMicros! / 1000000).toStringAsFixed(6).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}/${a.rateUnit!.shortLabel}',
                ),
              if (e.expectedClaimMinor != null)
                row(
                  'Expected claim (not actual received)',
                  earningsMoney(e.expectedClaimMinor),
                ),
              if (a.type == IncomeActivityType.work)
                row(
                  'Work / Salary',
                  'Associated work income. Commute distance does not make salary vehicle-generated profit.',
                ),
            ]),
            if (a.type != IncomeActivityType.simple) ...[
              section('Direct costs', [
                row(
                  a.directCostsComplete
                      ? 'Complete direct costs'
                      : 'Recorded costs — may be incomplete',
                  earningsMoney(e.directCostsMinor),
                ),
                FutureBuilder(
                  future: c.incomeExpenses(income.id),
                  builder: (context, expenses) => Column(
                    children: [
                      for (final expense in expenses.data ?? [])
                        ListTile(
                          title: Text(
                            '${earningsMoney(expense.amountMinor)} · ${expense.merchant ?? 'Expense'}',
                          ),
                          subtitle: Text(
                            DTFormatters.date(expense.eventDateTime),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => AppNavigation.openExpense(
                            context,
                            expense: expense,
                          ),
                        ),
                    ],
                  ),
                ),
              ]),
              section('Calculated metrics', [
                row('Net after direct costs', earningsMoney(e.netMinor)),
                if (!a.directCostsComplete)
                  row(
                    'Cost coverage',
                    'Unknown/incomplete. Mark costs complete in Edit before using net metrics.',
                  ),
                row(
                  'Gross per ${unit.shortLabel}',
                  earningsMoney(e.grossPerDistance(unit)),
                ),
                row(
                  'Net per ${unit.shortLabel}',
                  earningsMoney(e.netPerDistance(unit)),
                ),
                if (a.type != IncomeActivityType.reimbursement) ...[
                  row('Gross per hour', earningsMoney(e.grossPerHour)),
                  row('Net per hour', earningsMoney(e.netPerHour)),
                ],
                if (a.type == IncomeActivityType.delivery)
                  row('Income per delivery', earningsMoney(e.perDelivery)),
              ]),
            ],
          ],
        );
      },
    );
  }
}
