import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/utilities/formatters.dart';
import '../../../shared/widgets/dt_activity_row.dart';
import '../../../shared/widgets/dt_empty_state.dart';
import '../../../shared/widgets/dt_primary_button.dart';
import '../../../shared/widgets/dt_section_header.dart';
import '../../daily_records/domain/daily_activity.dart';
import '../../daily_records/domain/fuel_economy_calculator.dart';
import '../../daily_records/domain/monthly_spending.dart';
import '../../maintenance/domain/maintenance_reminder.dart';
import '../../vehicles/domain/vehicle.dart';
import '../../vehicles/presentation/vehicle_selector_sheet.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    final vehicle = controller.selectedVehicle;

    if (vehicle == null) {
      return Scaffold(
        body: SafeArea(
          child: DTEmptyState(
            icon: Icons.directions_car_filled_rounded,
            title: 'No active vehicle',
            body: 'Add another vehicle to continue tracking, or review archived vehicles from More.',
            action: DTPrimaryButton(
              label: 'Add vehicle',
              icon: Icons.add_rounded,
              onPressed: () => AppNavigation.openAddVehicle(context),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: _HomeDashboardContent(controller: controller, vehicle: vehicle),
      ),
    );
  }
}

class _HomeDashboardContent extends StatelessWidget {
  const _HomeDashboardContent({
    required this.controller,
    required this.vehicle,
  });

  final DriveTrackerController controller;
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final unit = vehicle.distanceUnit;
    return ListView(
      key: const Key('homeDashboardList'),
      padding: const EdgeInsets.fromLTRB(
        DTSpacing.lg,
        DTSpacing.md,
        DTSpacing.lg,
        DTSpacing.xxxl,
      ),
      children: [
        _VehicleHero(
          vehicle: vehicle,
          hasMultipleVehicles: controller.activeVehicles.length > 1,
          onTap: () => showVehicleSelectorSheet(context),
        ),
        const SizedBox(height: DTSpacing.md),
        _OdometerHero(
          odometer: controller.currentOdometer,
          unit: unit,
          onUpdate: () => AppNavigation.openUpdateOdometer(context),
        ),
        const SizedBox(height: DTSpacing.md),
        _MetricStrip(
          monthSpendMinor: controller.monthSpendMinor,
          latestFuelPriceMicrosPerLitre:
              controller.latestFuelPriceMicrosPerLitre,
          latestFuelEconomyInterval: controller.latestFuelEconomyInterval,
        ),
        const SizedBox(height: DTSpacing.sm),
        const DTSectionHeader(title: 'Maintenance'),
        _MaintenanceAttentionTile(
          reminder: controller.nextMaintenanceAttention,
          vehicle: vehicle,
        ),
        const SizedBox(height: DTSpacing.sm),
        const DTSectionHeader(title: 'Spending trend'),
        _SpendingTrendPanel(trend: controller.spendingTrend),
        const SizedBox(height: DTSpacing.sm),
        DTSectionHeader(
          title: 'Recent activity',
          action: Semantics(
            button: true,
            label: 'View all activity history',
            child: TextButton.icon(
              key: const Key('homeViewAllHistoryButton'),
              onPressed: () => AppNavigation.openHistory(context),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('View all'),
            ),
          ),
        ),
        _RecentActivityList(
          activities: controller.recentActivity,
          unit: unit,
          now: controller.currentTime,
        ),
      ],
    );
  }
}

class _VehicleHero extends StatelessWidget {
  const _VehicleHero({
    required this.vehicle,
    required this.hasMultipleVehicles,
    required this.onTap,
  });

  final Vehicle vehicle;
  final bool hasMultipleVehicles;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final switchLabel = hasMultipleVehicles ? 'Switch' : 'Manage';

    return Semantics(
      button: true,
      label:
          'Selected vehicle ${vehicle.name}, ${vehicle.description}, ${vehicle.registrationLabel}',
      child: Material(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: DTRadii.cardRadius,
        child: InkWell(
          key: const Key('selectedVehicleButton'),
          onTap: onTap,
          borderRadius: DTRadii.cardRadius,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              DTSpacing.lg,
              DTSpacing.md,
              DTSpacing.md,
              DTSpacing.md,
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.68),
                    borderRadius: BorderRadius.circular(DTRadii.card),
                  ),
                  child: Icon(
                    Icons.directions_car_filled_rounded,
                    color: colors.onPrimaryContainer,
                    size: 30,
                  ),
                ),
                const SizedBox(width: DTSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'DriveTracker',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: DTSpacing.xs),
                          Text(
                            'Home',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        vehicle.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: DTSpacing.xs),
                      Text(
                        _joinDisplay([
                          vehicle.description,
                          vehicle.registrationLabel,
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: DTSpacing.sm),
                Tooltip(
                  message: hasMultipleVehicles
                      ? 'Switch vehicle'
                      : 'Vehicle options',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DTSpacing.sm,
                      vertical: DTSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(DTRadii.card),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          switchLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          hasMultipleVehicles
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.more_horiz_rounded,
                          size: DTIconSizes.sm,
                          color: colors.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OdometerHero extends StatelessWidget {
  const _OdometerHero({
    required this.odometer,
    required this.unit,
    required this.onUpdate,
  });

  final int? odometer;
  final DistanceUnit unit;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.speed_rounded,
              size: DTIconSizes.sm,
              color: colors.primary,
            ),
            const SizedBox(width: DTSpacing.xs),
            Text(
              'Current odometer',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: DTSpacing.xs),
        _OdometerText(
          value: DTFormatters.odometer(odometer, unit),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
    final updateButton = Semantics(
      button: true,
      label: 'Update odometer',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: FilledButton.tonalIcon(
          key: const Key('homeUpdateOdometerButton'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: DTSpacing.md),
          ),
          onPressed: onUpdate,
          icon: const Icon(Icons.add_road_rounded),
          label: const Text('Update'),
        ),
      ),
    );

    return Semantics(
      container: true,
      label: 'Current odometer ${DTFormatters.odometer(odometer, unit)}',
      child: Material(
        key: const Key('homeOdometerPanel'),
        color: colors.primaryContainer.withValues(
          alpha: colors.brightness == Brightness.dark ? 0.28 : 0.42,
        ),
        borderRadius: DTRadii.cardRadius,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            DTSpacing.lg,
            DTSpacing.md,
            DTSpacing.md,
            DTSpacing.md,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 320) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    content,
                    const SizedBox(height: DTSpacing.sm),
                    updateButton,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: content),
                  const SizedBox(width: DTSpacing.sm),
                  updateButton,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OdometerText extends StatelessWidget {
  const _OdometerText({required this.value, required this.style});

  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(value, maxLines: 1, style: style),
      ),
    );
  }
}

class _MetricStrip extends StatelessWidget {
  const _MetricStrip({
    required this.monthSpendMinor,
    required this.latestFuelPriceMicrosPerLitre,
    required this.latestFuelEconomyInterval,
  });

  final int monthSpendMinor;
  final int? latestFuelPriceMicrosPerLitre;
  final FuelEconomyInterval? latestFuelEconomyInterval;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _MetricData(
        key: const Key('homeMonthSpendMetric'),
        icon: Icons.payments_rounded,
        label: 'This month',
        value: DTFormatters.moneyMinor(monthSpendMinor),
        support: 'Fuel + costs',
      ),
      _MetricData(
        key: const Key('homeFuelPriceMetric'),
        icon: Icons.local_gas_station_rounded,
        label: 'Fuel',
        value: latestFuelPriceMicrosPerLitre == null
            ? 'No fuel data'
            : DTFormatters.fuelPrice(latestFuelPriceMicrosPerLitre),
        support: 'Latest price',
      ),
      _MetricData(
        key: const Key('homeFuelEconomyMetric'),
        icon: Icons.speed_rounded,
        label: 'Economy',
        value: latestFuelEconomyInterval == null
            ? 'Not enough data'
            : DTFormatters.ukMpg(latestFuelEconomyInterval!.ukMpg),
        support: latestFuelEconomyInterval == null
            ? 'Full-to-full needed'
            : 'Full-to-full MPG',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 340) {
          return Column(
            children: [
              _MetricTile(data: metrics[0]),
              const SizedBox(height: DTSpacing.sm),
              Row(
                children: [
                  Expanded(child: _MetricTile(data: metrics[1])),
                  const SizedBox(width: DTSpacing.sm),
                  Expanded(child: _MetricTile(data: metrics[2])),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            for (var index = 0; index < metrics.length; index += 1) ...[
              if (index > 0) const SizedBox(width: DTSpacing.sm),
              Expanded(child: _MetricTile(data: metrics[index])),
            ],
          ],
        );
      },
    );
  }
}

class _MetricData {
  const _MetricData({
    required this.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.support,
  });

  final Key key;
  final IconData icon;
  final String label;
  final String value;
  final String support;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.data});

  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      container: true,
      label: '${data.label}: ${data.value}',
      child: Material(
        key: data.key,
        color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: DTRadii.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(DTSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(data.icon, size: DTIconSizes.sm, color: colors.primary),
                  const SizedBox(width: DTSpacing.xs),
                  Expanded(
                    child: Text(
                      data.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DTSpacing.sm),
              Text(
                data.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                data.support,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaintenanceAttentionTile extends StatelessWidget {
  const _MaintenanceAttentionTile({
    required this.reminder,
    required this.vehicle,
  });

  final MaintenanceReminder? reminder;
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final reminder = this.reminder;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (reminder == null) {
      return Semantics(
        button: true,
        label: 'Maintenance, no maintenance due soon',
        child: Material(
          key: const Key('homeMaintenanceAttentionTile'),
          color: colors.surfaceContainerHighest.withValues(alpha: 0.34),
          borderRadius: DTRadii.cardRadius,
          child: InkWell(
            borderRadius: DTRadii.cardRadius,
            onTap: () => AppNavigation.openMaintenance(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DTSpacing.md,
                vertical: DTSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    color: colors.primary,
                    size: DTIconSizes.md,
                  ),
                  const SizedBox(width: DTSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No maintenance due soon',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Tracked intervals look clear',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: DTSpacing.sm),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final progress = reminder.intervalProgress;
    final statusColor = _maintenanceColor(context, reminder.state);
    final subtitle = _maintenanceSubtitle(reminder, vehicle);
    return Semantics(
      button: true,
      label: 'Maintenance ${reminder.item.name}, ${reminder.state.label}',
      value: progress == null
          ? subtitle
          : '${(progress * 100).round()} percent through interval',
      child: Material(
        key: const Key('homeMaintenanceAttentionTile'),
        color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: DTRadii.cardRadius,
        child: InkWell(
          borderRadius: DTRadii.cardRadius,
          onTap: () => AppNavigation.openMaintenanceItemDetails(
            context,
            reminder.item.id,
          ),
          child: Padding(
            padding: const EdgeInsets.all(DTSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_maintenanceIcon(reminder.state), color: statusColor),
                    const SizedBox(width: DTSpacing.sm),
                    Expanded(
                      child: Text(
                        reminder.item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: DTSpacing.sm),
                    _StatusPill(
                      label: reminder.state.label,
                      color: statusColor,
                    ),
                  ],
                ),
                const SizedBox(height: DTSpacing.xs),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (progress != null) ...[
                  const SizedBox(height: DTSpacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(DTRadii.card),
                    child: LinearProgressIndicator(
                      key: const Key('homeMaintenanceProgress'),
                      value: progress,
                      minHeight: 6,
                      color: statusColor,
                      backgroundColor: colors.outlineVariant.withValues(
                        alpha: 0.45,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
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
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(DTRadii.card),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SpendingTrendPanel extends StatefulWidget {
  const _SpendingTrendPanel({required this.trend});

  final List<MonthlySpending> trend;

  @override
  State<_SpendingTrendPanel> createState() => _SpendingTrendPanelState();
}

class _SpendingTrendPanelState extends State<_SpendingTrendPanel> {
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = _defaultSelectedIndex(widget.trend);
  }

  @override
  void didUpdateWidget(_SpendingTrendPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_trendSignature(oldWidget.trend) != _trendSignature(widget.trend) ||
        (_selectedIndex ?? 0) >= widget.trend.length) {
      _selectedIndex = _defaultSelectedIndex(widget.trend);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasData = widget.trend.any((bucket) => bucket.hasSpend);

    if (!hasData) {
      return Material(
        key: const Key('homeSpendingTrendEmpty'),
        color: colors.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: DTRadii.cardRadius,
        child: const Padding(
          padding: EdgeInsets.all(DTSpacing.md),
          child: Text('No spending trend yet'),
        ),
      );
    }

    final selectedIndex = (_selectedIndex ?? widget.trend.length - 1)
        .clamp(0, widget.trend.length - 1)
        .toInt();
    final selected = widget.trend[selectedIndex];
    final maxAmount = widget.trend
        .map((bucket) => bucket.amountMinor)
        .reduce((a, b) => a > b ? a : b);

    return Semantics(
      container: true,
      label: 'Spending trend for the last ${widget.trend.length} months',
      child: Material(
        key: const Key('homeSpendingTrend'),
        color: colors.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: DTRadii.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(DTSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_monthAbbreviation(selected.month)} · ${DTFormatters.moneyMinor(selected.amountMinor)} spent',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: DTSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var index = 0; index < widget.trend.length; index += 1)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DTSpacing.xs,
                        ),
                        child: _SpendingTrendBar(
                          bucket: widget.trend[index],
                          maxAmountMinor: maxAmount,
                          selected: index == selectedIndex,
                          onTap: () => setState(() => _selectedIndex = index),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _defaultSelectedIndex(List<MonthlySpending> trend) {
    if (trend.isEmpty) {
      return 0;
    }
    for (var index = trend.length - 1; index >= 0; index -= 1) {
      if (trend[index].hasSpend) {
        return index;
      }
    }
    return trend.length - 1;
  }

  String _trendSignature(List<MonthlySpending> trend) {
    return trend
        .map(
          (bucket) =>
              '${bucket.month.year}-${bucket.month.month}:${bucket.amountMinor}',
        )
        .join('|');
  }
}

class _SpendingTrendBar extends StatelessWidget {
  const _SpendingTrendBar({
    required this.bucket,
    required this.maxAmountMinor,
    required this.selected,
    required this.onTap,
  });

  final MonthlySpending bucket;
  final int maxAmountMinor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ratio = maxAmountMinor == 0
        ? 0.0
        : bucket.amountMinor / maxAmountMinor;
    final targetHeight = bucket.amountMinor == 0 ? 4.0 : 14.0 + (58.0 * ratio);
    final barColor = selected ? colors.tertiary : colors.primary;
    final valueVisible = bucket.amountMinor > 0 || selected;
    final month = _monthAbbreviation(bucket.month);
    final value = DTFormatters.moneyMinor(bucket.amountMinor);

    return Semantics(
      button: true,
      selected: selected,
      label: '$month ${bucket.month.year}, $value spent',
      child: InkWell(
        key: Key('homeTrendMonth_${bucket.month.year}_${bucket.month.month}'),
        borderRadius: BorderRadius.circular(DTRadii.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: DTSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 18,
                child: valueVisible
                    ? FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          value,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: selected
                                ? colors.onSurface
                                : colors.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: DTSpacing.xs),
              SizedBox(
                height: 78,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    key: Key(
                      'homeTrendBar_${bucket.month.year}_${bucket.month.month}',
                    ),
                    width: selected ? 14 : 10,
                    height: targetHeight,
                    decoration: BoxDecoration(
                      color: bucket.amountMinor == 0
                          ? colors.outlineVariant
                          : barColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(DTRadii.card),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: DTSpacing.xs),
              Text(
                month,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: selected ? colors.onSurface : colors.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentActivityList extends StatelessWidget {
  const _RecentActivityList({
    required this.activities,
    required this.unit,
    required this.now,
  });

  final List<DailyActivity> activities;
  final DistanceUnit unit;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) {
      return const Padding(
        key: Key('homeRecentActivityEmpty'),
        padding: EdgeInsets.only(top: DTSpacing.md),
        child: Text('No activity yet. Use + to add fuel, costs or service.'),
      );
    }

    return Column(
      key: const Key('homeRecentActivityList'),
      children: [
        for (final activity in activities)
          _ActivityTile(activity: activity, unit: unit, now: now),
      ],
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.activity,
    required this.unit,
    required this.now,
  });

  final DailyActivity activity;
  final DistanceUnit unit;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final row = DTActivityRow(
      icon: _iconForActivity(activity.type),
      title: activity.title,
      subtitle: _activitySubtitle(activity, unit, now),
      trailing: _activityTrailing(context, activity),
    );
    final canOpen =
        activity.type != DailyActivityType.odometer &&
        activity.type != DailyActivityType.all;

    if (!canOpen) {
      return Semantics(
        label: '${activity.title}, ${_activitySubtitle(activity, unit, now)}',
        child: row,
      );
    }

    return Semantics(
      button: true,
      label: '${activity.title}, ${_activitySubtitle(activity, unit, now)}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('homeActivity_${activity.type.name}_${activity.recordId}'),
          borderRadius: DTRadii.cardRadius,
          onTap: () => _openActivity(context, activity),
          child: row,
        ),
      ),
    );
  }
}

Future<void> _openActivity(BuildContext context, DailyActivity activity) async {
  final controller = context.read<DriveTrackerController>();
  switch (activity.type) {
    case DailyActivityType.refuel:
      final refuel = await controller.refuelById(activity.recordId);
      if (refuel != null && context.mounted) {
        await AppNavigation.openRefuel(context, refuel: refuel);
      }
      break;
    case DailyActivityType.expense:
      final expense = await controller.expenseById(activity.recordId);
      if (expense != null && context.mounted) {
        await AppNavigation.openExpense(context, expense: expense);
      }
      break;
    case DailyActivityType.income:
      final income = await controller.incomeById(activity.recordId);
      if (income != null && context.mounted) {
        await AppNavigation.openIncome(context, income: income);
      }
      break;
    case DailyActivityType.service:
      final service = await controller.serviceRecordById(activity.recordId);
      if (service != null && context.mounted) {
        await AppNavigation.openService(context, service: service);
      }
      break;
    case DailyActivityType.odometer:
    case DailyActivityType.all:
      break;
  }
}

IconData _iconForActivity(DailyActivityType type) {
  return switch (type) {
    DailyActivityType.refuel => Icons.local_gas_station_rounded,
    DailyActivityType.expense => Icons.payments_outlined,
    DailyActivityType.income => Icons.work_outline_rounded,
    DailyActivityType.service => Icons.build_circle_outlined,
    DailyActivityType.odometer => Icons.speed_rounded,
    DailyActivityType.all => Icons.history_rounded,
  };
}

String _activitySubtitle(
  DailyActivity activity,
  DistanceUnit unit,
  DateTime now,
) {
  final parts = [
    DTFormatters.activityDateTime(activity.eventDateTime, now: now),
    activity.subtitle,
    if (activity.odometer != null)
      DTFormatters.odometer(activity.odometer, unit),
  ];
  return _joinDisplay(parts);
}

Widget? _activityTrailing(BuildContext context, DailyActivity activity) {
  final amount = activity.amountMinor;
  if (amount == null) {
    return null;
  }
  final colors = Theme.of(context).colorScheme;
  final isIncome = activity.type == DailyActivityType.income;
  return Text(
    isIncome
        ? '+${DTFormatters.moneyMinor(amount)}'
        : DTFormatters.moneyMinor(amount),
    textAlign: TextAlign.end,
    style: Theme.of(context).textTheme.labelLarge?.copyWith(
      color: isIncome ? colors.tertiary : colors.onSurface,
      fontWeight: FontWeight.w900,
    ),
  );
}

String _maintenanceSubtitle(MaintenanceReminder reminder, Vehicle vehicle) {
  final parts = <String>[
    if (reminder.nextMileageDue != null)
      'Due at ${DTFormatters.odometer(reminder.nextMileageDue, vehicle.distanceUnit)}',
    if (reminder.nextDateDue != null) DTFormatters.date(reminder.nextDateDue!),
    _maintenanceRemaining(reminder, vehicle),
  ];
  return _joinDisplay(parts);
}

String _maintenanceRemaining(MaintenanceReminder reminder, Vehicle vehicle) {
  if (reminder.primaryBasis == MaintenanceReminderBasis.mileage &&
      reminder.milesRemaining != null) {
    final remaining = reminder.milesRemaining!;
    if (remaining < 0) {
      return 'Overdue by ${DTFormatters.odometer(-remaining, vehicle.distanceUnit)}';
    }
    if (remaining == 0) {
      return 'Due now';
    }
    return '${DTFormatters.odometer(remaining, vehicle.distanceUnit)} remaining';
  }

  final days = reminder.daysRemaining;
  if (days == null) {
    return reminder.item.hasInterval && reminder.item.reminderEnabled
        ? 'Add a baseline or service'
        : '';
  }
  if (days < 0) {
    return 'Overdue by ${-days} days';
  }
  if (days == 0) {
    return 'Due today';
  }
  return 'Due in $days days';
}

IconData _maintenanceIcon(MaintenanceReminderState state) {
  return switch (state) {
    MaintenanceReminderState.overdue => Icons.error_outline_rounded,
    MaintenanceReminderState.due => Icons.notification_important_outlined,
    MaintenanceReminderState.dueSoon => Icons.schedule_rounded,
    MaintenanceReminderState.upcoming => Icons.upcoming_rounded,
    MaintenanceReminderState.normal => Icons.check_circle_outline_rounded,
  };
}

Color _maintenanceColor(BuildContext context, MaintenanceReminderState state) {
  final colors = Theme.of(context).colorScheme;
  return switch (state) {
    MaintenanceReminderState.overdue => colors.error,
    MaintenanceReminderState.due => colors.error,
    MaintenanceReminderState.dueSoon => colors.tertiary,
    MaintenanceReminderState.upcoming => colors.primary,
    MaintenanceReminderState.normal => colors.onSurfaceVariant,
  };
}

String _monthAbbreviation(DateTime value) {
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
  return months[value.month - 1];
}

String _joinDisplay(List<String?> parts) {
  return parts
      .where((part) => part != null && part.trim().isNotEmpty)
      .map((part) => part!.trim())
      .join(' · ');
}
