import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/utilities/formatters.dart';
import '../../../shared/widgets/dt_activity_row.dart';
import '../../../shared/widgets/dt_empty_state.dart';
import '../../vehicles/domain/vehicle.dart';
import '../domain/daily_activity.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  var _filter = DailyActivityType.all;
  Future<List<DailyActivity>>? _activitiesFuture;
  String? _loadedVehicleId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    final vehicle = controller.selectedVehicle;

    if (vehicle == null) {
      return const Scaffold(
        appBar: _HistoryAppBar(),
        body: DTEmptyState(
          icon: Icons.history_rounded,
          title: 'No active vehicle',
          body: 'Select an active vehicle before reviewing history.',
        ),
      );
    }

    if (_activitiesFuture == null || _loadedVehicleId != vehicle.id) {
      _loadedVehicleId = vehicle.id;
      _activitiesFuture = controller.historyForSelectedVehicle(type: _filter);
    }

    return Scaffold(
      appBar: const _HistoryAppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            DTSpacing.lg,
            DTSpacing.lg,
            DTSpacing.lg,
            DTSpacing.xxxl,
          ),
          children: [
            Text(
              vehicle.name,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: DTSpacing.xs),
            Text(
              vehicle.description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: DTSpacing.lg),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<DailyActivityType>(
                key: const Key('historyFilterField'),
                selected: {_filter},
                segments: const [
                  ButtonSegment(
                    value: DailyActivityType.all,
                    label: Text('All'),
                  ),
                  ButtonSegment(
                    value: DailyActivityType.refuel,
                    label: Text('Fuel'),
                  ),
                  ButtonSegment(
                    value: DailyActivityType.expense,
                    label: Text('Expense'),
                  ),
                  ButtonSegment(
                    value: DailyActivityType.income,
                    label: Text('Income'),
                  ),
                ],
                onSelectionChanged: (selection) {
                  setState(() {
                    _filter = selection.first;
                    _activitiesFuture = controller.historyForSelectedVehicle(
                      type: _filter,
                    );
                  });
                },
              ),
            ),
            const SizedBox(height: DTSpacing.lg),
            FutureBuilder<List<DailyActivity>>(
              future: _activitiesFuture,
              builder: (context, snapshot) {
                final activities = snapshot.data;
                if (activities == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (activities.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: DTSpacing.xl),
                    child: Text('No records saved for this view yet.'),
                  );
                }
                return _ActivityList(
                  vehicle: vehicle,
                  activities: activities,
                  onTap: _openActivity,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openActivity(DailyActivity activity) async {
    final controller = context.read<DriveTrackerController>();
    switch (activity.type) {
      case DailyActivityType.refuel:
        final refuel = await controller.refuelById(activity.recordId);
        if (refuel != null && mounted) {
          await AppNavigation.openRefuel(context, refuel: refuel);
        }
        break;
      case DailyActivityType.expense:
        final expense = await controller.expenseById(activity.recordId);
        if (expense != null && mounted) {
          await AppNavigation.openExpense(context, expense: expense);
        }
        break;
      case DailyActivityType.income:
        final income = await controller.incomeById(activity.recordId);
        if (income != null && mounted) {
          await AppNavigation.openIncome(context, income: income);
        }
        break;
      case DailyActivityType.odometer:
      case DailyActivityType.all:
        break;
    }
    if (mounted) {
      setState(() {
        _activitiesFuture = controller.historyForSelectedVehicle(type: _filter);
      });
    }
  }
}

class _HistoryAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _HistoryAppBar();

  @override
  Widget build(BuildContext context) {
    return AppBar(title: const Text('History'));
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({
    required this.vehicle,
    required this.activities,
    required this.onTap,
  });

  final Vehicle vehicle;
  final List<DailyActivity> activities;
  final ValueChanged<DailyActivity> onTap;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    String? currentMonth;
    for (final activity in activities) {
      final month = _monthLabel(activity.eventDateTime);
      if (month != currentMonth) {
        currentMonth = month;
        children.add(
          Padding(
            padding: const EdgeInsets.only(
              top: DTSpacing.lg,
              bottom: DTSpacing.sm,
            ),
            child: Text(
              month,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        );
      }

      children.add(
        InkWell(
          key: Key(
            'historyActivity_${activity.type.name}_${activity.recordId}',
          ),
          onTap: activity.type == DailyActivityType.odometer
              ? null
              : () => onTap(activity),
          child: DTActivityRow(
            icon: _iconFor(activity.type),
            title: activity.title,
            subtitle: _subtitle(activity, vehicle),
            trailing: _trailing(context, activity),
          ),
        ),
      );
    }
    return Column(children: children);
  }

  Widget? _trailing(BuildContext context, DailyActivity activity) {
    final amount = activity.amountMinor;
    if (amount == null) {
      return null;
    }
    final color = activity.type == DailyActivityType.income
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.onSurface;
    return Text(
      DTFormatters.moneyMinor(amount),
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: color, fontWeight: FontWeight.w800),
    );
  }

  String _subtitle(DailyActivity activity, Vehicle vehicle) {
    final parts = <String>[
      DTFormatters.dateTime(activity.eventDateTime),
      activity.subtitle,
      if (activity.odometer != null)
        DTFormatters.odometer(activity.odometer, vehicle.distanceUnit),
    ];
    return parts.where((part) => part.trim().isNotEmpty).join(' / ');
  }

  IconData _iconFor(DailyActivityType type) {
    return switch (type) {
      DailyActivityType.refuel => Icons.local_gas_station_rounded,
      DailyActivityType.expense => Icons.payments_outlined,
      DailyActivityType.income => Icons.work_outline_rounded,
      DailyActivityType.odometer => Icons.speed_rounded,
      DailyActivityType.all => Icons.history_rounded,
    };
  }

  String _monthLabel(DateTime value) {
    final local = value.toLocal();
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[local.month - 1]} ${local.year}';
  }
}
