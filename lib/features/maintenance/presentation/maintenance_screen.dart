import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/utilities/formatters.dart';
import '../../../shared/widgets/dt_empty_state.dart';
import '../../../shared/widgets/dt_list_card.dart';
import '../../../shared/widgets/dt_primary_button.dart';
import '../../../shared/widgets/dt_section_header.dart';
import '../../../shared/widgets/dt_status_badge.dart';
import '../../vehicles/domain/vehicle.dart';
import '../domain/maintenance_reminder.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  Future<List<MaintenanceReminder>>? _remindersFuture;
  String? _loadedVehicleId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    final vehicle = controller.selectedVehicle;

    if (vehicle == null) {
      return const Scaffold(
        appBar: _MaintenanceAppBar(),
        body: DTEmptyState(
          icon: Icons.handyman_rounded,
          title: 'No active vehicle',
          body: 'Select an active vehicle before setting up maintenance.',
        ),
      );
    }

    if (_remindersFuture == null || _loadedVehicleId != vehicle.id) {
      _loadedVehicleId = vehicle.id;
      _remindersFuture = controller.maintenanceRemindersForSelectedVehicle();
    }

    return Scaffold(
      appBar: const _MaintenanceAppBar(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
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
                'Maintenance items and intervals',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: DTSpacing.lg),
              DTPrimaryButton(
                key: const Key('maintenanceAddButton'),
                label: 'Add maintenance item',
                icon: Icons.add_rounded,
                onPressed: () async {
                  await AppNavigation.openAddMaintenanceItem(context);
                  if (mounted) {
                    await _refresh();
                  }
                },
              ),
              const DTSectionHeader(title: 'Items'),
              FutureBuilder<List<MaintenanceReminder>>(
                future: _remindersFuture,
                builder: (context, snapshot) {
                  final reminders = snapshot.data;
                  if (reminders == null) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: DTSpacing.xl),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (reminders.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.only(top: DTSpacing.lg),
                      child: Text('No maintenance items have been added yet.'),
                    );
                  }
                  return Column(
                    children: [
                      for (final reminder in reminders)
                        _MaintenanceReminderTile(
                          reminder: reminder,
                          vehicle: vehicle,
                          onTap: () async {
                            await AppNavigation.openMaintenanceItemDetails(
                              context,
                              reminder.item.id,
                            );
                            if (mounted) {
                              await _refresh();
                            }
                          },
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    final controller = context.read<DriveTrackerController>();
    final future = controller.maintenanceRemindersForSelectedVehicle();
    setState(() {
      _remindersFuture = future;
    });
    await future;
  }
}

class _MaintenanceAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _MaintenanceAppBar();

  @override
  Widget build(BuildContext context) {
    return AppBar(title: const Text('Maintenance'));
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _MaintenanceReminderTile extends StatelessWidget {
  const _MaintenanceReminderTile({
    required this.reminder,
    required this.vehicle,
    required this.onTap,
  });

  final MaintenanceReminder reminder;
  final Vehicle vehicle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stateLabel = reminder.shouldShowAsReminder
        ? reminder.state.label
        : 'No reminder';
    final color = _colorForState(context, reminder.state);
    return Padding(
      key: Key('maintenanceItem_${reminder.item.id}'),
      padding: const EdgeInsets.only(bottom: DTSpacing.sm),
      child: DTListCard(
        icon: _iconForState(reminder.state),
        title: reminder.item.name,
        subtitle: _reminderSubtitle(reminder, vehicle),
        accentColor: color,
        trailing: DTStatusBadge(
          label: stateLabel,
          color: color,
          icon: reminder.shouldShowAsReminder
              ? _iconForState(reminder.state)
              : Icons.notifications_off_outlined,
          compact: true,
        ),
        onTap: onTap,
      ),
    );
  }
}

String _reminderSubtitle(MaintenanceReminder reminder, Vehicle vehicle) {
  final item = reminder.item;
  final parts = <String>[
    if (item.category != null) item.category!,
    if (!item.reminderEnabled) 'Reminder off',
    if (!item.hasInterval) 'No interval',
    if (reminder.nextMileageDue != null)
      'Due at ${DTFormatters.odometer(reminder.nextMileageDue, vehicle.distanceUnit)}',
    if (reminder.nextDateDue != null) DTFormatters.date(reminder.nextDateDue!),
    _remainingText(reminder, vehicle),
  ];
  return parts.where((part) => part.trim().isNotEmpty).join(' / ');
}

String _remainingText(MaintenanceReminder reminder, Vehicle vehicle) {
  final miles = reminder.milesRemaining;
  final days = reminder.daysRemaining;
  if (miles == null && days == null) {
    return reminder.item.hasInterval && reminder.item.reminderEnabled
        ? 'Add a baseline or service'
        : '';
  }
  if (reminder.primaryBasis == MaintenanceReminderBasis.mileage &&
      miles != null) {
    if (miles < 0) {
      return 'Overdue by ${DTFormatters.odometer(-miles, vehicle.distanceUnit)}';
    }
    if (miles == 0) {
      return 'Due now';
    }
    return '${DTFormatters.odometer(miles, vehicle.distanceUnit)} remaining';
  }
  if (days == null) {
    return '';
  }
  if (days < 0) {
    return 'Overdue by ${-days} days';
  }
  if (days == 0) {
    return 'Due today';
  }
  return 'Due in $days days';
}

IconData _iconForState(MaintenanceReminderState state) {
  return switch (state) {
    MaintenanceReminderState.overdue => Icons.error_outline_rounded,
    MaintenanceReminderState.due => Icons.notification_important_outlined,
    MaintenanceReminderState.dueSoon => Icons.schedule_rounded,
    MaintenanceReminderState.upcoming => Icons.upcoming_rounded,
    MaintenanceReminderState.normal => Icons.check_circle_outline_rounded,
  };
}

Color _colorForState(BuildContext context, MaintenanceReminderState state) {
  final colors = Theme.of(context).colorScheme;
  return switch (state) {
    MaintenanceReminderState.overdue => colors.error,
    MaintenanceReminderState.due => colors.error,
    MaintenanceReminderState.dueSoon => colors.tertiary,
    MaintenanceReminderState.upcoming => colors.primary,
    MaintenanceReminderState.normal => colors.onSurfaceVariant,
  };
}
