import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/utilities/formatters.dart';
import '../../../shared/widgets/dt_activity_row.dart';
import '../../../shared/widgets/dt_empty_state.dart';
import '../../../shared/widgets/dt_metric_card.dart';
import '../../../shared/widgets/dt_primary_button.dart';
import '../../../shared/widgets/dt_section_header.dart';
import '../../daily_records/domain/daily_activity.dart';
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

    final unit = vehicle.distanceUnit;
    final recentActivity = controller.recentActivity;
    final latestEconomy = controller.latestFuelEconomyInterval;
    final nextMaintenance = controller.nextMaintenanceAttention;

    return Scaffold(
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
              'Home',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: DTSpacing.lg),
            _VehicleSelectorButton(
              vehicleName: vehicle.name,
              description: vehicle.description,
              registration: vehicle.registrationLabel,
              onTap: () => showVehicleSelectorSheet(context),
            ),
            const SizedBox(height: DTSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: DTMetricCard(
                    icon: Icons.speed_rounded,
                    label: 'Current odometer',
                    value: DTFormatters.odometer(
                      controller.currentOdometer,
                      unit,
                    ),
                    supportingText: 'Highest saved reading',
                  ),
                ),
                const SizedBox(width: DTSpacing.md),
                Expanded(
                  child: DTMetricCard(
                    icon: Icons.payments_rounded,
                    label: 'This month',
                    value: DTFormatters.moneyMinor(controller.monthSpendMinor),
                    supportingText: 'Fuel, expenses and service',
                  ),
                ),
              ],
            ),
            const SizedBox(height: DTSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: DTMetricCard(
                    icon: Icons.local_gas_station_rounded,
                    label: 'Fuel price',
                    value: DTFormatters.fuelPrice(
                      controller.latestFuelPriceMicrosPerLitre,
                    ),
                    supportingText: 'Latest saved refuel',
                  ),
                ),
                const SizedBox(width: DTSpacing.md),
                Expanded(
                  child: DTMetricCard(
                    icon: Icons.speed_rounded,
                    label: 'Fuel economy',
                    value: DTFormatters.ukMpg(latestEconomy?.ukMpg),
                    supportingText: latestEconomy == null
                        ? 'Not enough fuel data yet'
                        : 'Latest full-to-full interval',
                  ),
                ),
              ],
            ),
            const SizedBox(height: DTSpacing.lg),
            DTPrimaryButton(
              key: const Key('homeUpdateOdometerButton'),
              label: 'Update odometer',
              icon: Icons.add_road_rounded,
              onPressed: () => AppNavigation.openUpdateOdometer(context),
            ),
            const DTSectionHeader(title: 'Maintenance'),
            _MaintenanceAttentionTile(
              reminder: nextMaintenance,
              vehicle: vehicle,
            ),
            const DTSectionHeader(title: 'Recent activity'),
            if (recentActivity.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: DTSpacing.lg),
                child: Text('No records have been saved yet.'),
              )
            else
              for (final activity in recentActivity)
                DTActivityRow(
                  icon: _iconForActivity(activity.type),
                  title: activity.title,
                  subtitle: _activitySubtitle(activity, unit),
                  trailing: _activityTrailing(context, activity),
                ),
          ],
        ),
      ),
    );
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

String _activitySubtitle(DailyActivity activity, DistanceUnit unit) {
  final parts = [
    DTFormatters.dateTime(activity.eventDateTime),
    activity.subtitle,
    if (activity.odometer != null)
      DTFormatters.odometer(activity.odometer, unit),
  ];
  return parts.where((part) => part.trim().isNotEmpty).join(' / ');
}

Widget? _activityTrailing(BuildContext context, DailyActivity activity) {
  final amount = activity.amountMinor;
  if (amount == null) {
    return null;
  }
  return Text(
    DTFormatters.moneyMinor(amount),
    style: Theme.of(context).textTheme.labelLarge
        ?.copyWith(fontWeight: FontWeight.w800),
  );
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
    if (reminder == null) {
      return ListTile(
        key: const Key('homeMaintenanceAttentionTile'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.check_circle_outline_rounded),
        title: const Text('No active maintenance reminders'),
        subtitle: const Text('Add intervals from More > Maintenance'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => AppNavigation.openMaintenance(context),
      );
    }

    return ListTile(
      key: const Key('homeMaintenanceAttentionTile'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(_maintenanceIcon(reminder.state)),
      title: Text(reminder.item.name),
      subtitle: Text(_maintenanceSubtitle(reminder, vehicle)),
      trailing: Text(
        reminder.state.label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: _maintenanceColor(context, reminder.state),
        ),
      ),
      onTap: () =>
          AppNavigation.openMaintenanceItemDetails(context, reminder.item.id),
    );
  }
}

String _maintenanceSubtitle(MaintenanceReminder reminder, Vehicle vehicle) {
  final parts = <String>[
    if (reminder.nextMileageDue != null)
      'Due at ${DTFormatters.odometer(reminder.nextMileageDue, vehicle.distanceUnit)}',
    if (reminder.nextDateDue != null) DTFormatters.date(reminder.nextDateDue!),
    _maintenanceRemaining(reminder, vehicle),
  ];
  return parts.where((part) => part.trim().isNotEmpty).join(' / ');
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

class _VehicleSelectorButton extends StatelessWidget {
  const _VehicleSelectorButton({
    required this.vehicleName,
    required this.description,
    required this.registration,
    required this.onTap,
  });

  final String vehicleName;
  final String description;
  final String registration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.46),
      borderRadius: DTRadii.cardRadius,
      child: InkWell(
        key: const Key('selectedVehicleButton'),
        onTap: onTap,
        borderRadius: DTRadii.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(DTSpacing.lg),
          child: Row(
            children: [
              Icon(
                Icons.directions_car_rounded,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: DTSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicleName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: DTSpacing.xs),
                    Text(
                      '$description  |  $registration',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
