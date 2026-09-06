import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/utilities/formatters.dart';
import '../../../shared/widgets/dt_empty_state.dart';
import '../../../shared/widgets/dt_section_header.dart';
import '../../maintenance/domain/maintenance_reminder.dart';
import '../../vehicles/domain/vehicle.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  Future<List<MaintenanceReminder>>? _remindersFuture;
  String? _loadedVehicleId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    final vehicle = controller.selectedVehicle;

    if (vehicle == null) {
      return const Scaffold(
        body: SafeArea(
          child: DTEmptyState(
            icon: Icons.notifications_none_rounded,
            title: 'No active vehicle',
            body: 'Select an active vehicle before reviewing reminders.',
          ),
        ),
      );
    }

    if (_remindersFuture == null || _loadedVehicleId != vehicle.id) {
      _loadedVehicleId = vehicle.id;
      _remindersFuture = controller.maintenanceRemindersForSelectedVehicle();
    }

    return Scaffold(
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
                'Reminders',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: DTSpacing.xs),
              Text(
                vehicle.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: DTSpacing.lg),
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
                  final visible = reminders
                      .where((reminder) => reminder.shouldShowAsReminder)
                      .toList();
                  if (visible.isEmpty) {
                    return const DTEmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: 'No active reminders',
                      body: 'Add maintenance intervals to start tracking due work.',
                    );
                  }

                  final needsSetup = visible
                      .where(
                        (reminder) =>
                            reminder.nextMileageDue == null &&
                            reminder.nextDateDue == null,
                      )
                      .toList();
                  final needsAttention = visible
                      .where(
                        (reminder) =>
                            reminder.nextMileageDue != null ||
                            reminder.nextDateDue != null,
                      )
                      .where(
                        (reminder) =>
                            reminder.state.severity >=
                            MaintenanceReminderState.dueSoon.severity,
                      )
                      .toList();
                  final upcoming = visible
                      .where(
                        (reminder) =>
                            reminder.nextMileageDue != null ||
                            reminder.nextDateDue != null,
                      )
                      .where(
                        (reminder) =>
                            reminder.state == MaintenanceReminderState.upcoming,
                      )
                      .toList();
                  final allGood = visible
                      .where(
                        (reminder) =>
                            reminder.nextMileageDue != null ||
                            reminder.nextDateDue != null,
                      )
                      .where(
                        (reminder) =>
                            reminder.state == MaintenanceReminderState.normal,
                      )
                      .toList();

                  return Column(
                    children: [
                      _ReminderSection(
                        title: 'Needs attention',
                        reminders: needsAttention,
                        vehicle: vehicle,
                        onRefresh: _refresh,
                      ),
                      _ReminderSection(
                        title: 'Upcoming',
                        reminders: upcoming,
                        vehicle: vehicle,
                        onRefresh: _refresh,
                      ),
                      _ReminderSection(
                        title: 'Needs setup',
                        reminders: needsSetup,
                        vehicle: vehicle,
                        onRefresh: _refresh,
                      ),
                      _ReminderSection(
                        title: 'All good',
                        reminders: allGood,
                        vehicle: vehicle,
                        onRefresh: _refresh,
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

class _ReminderSection extends StatelessWidget {
  const _ReminderSection({
    required this.title,
    required this.reminders,
    required this.vehicle,
    required this.onRefresh,
  });

  final String title;
  final List<MaintenanceReminder> reminders;
  final Vehicle vehicle;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (reminders.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DTSectionHeader(title: title),
        for (final reminder in reminders)
          ListTile(
            key: Key('reminder_${reminder.item.id}'),
            leading: Icon(_iconForState(reminder.state)),
            title: Text(reminder.item.name),
            subtitle: Text(_reminderSubtitle(reminder, vehicle)),
            trailing: TextButton.icon(
              key: Key('recordService_${reminder.item.id}'),
              onPressed: () async {
                await AppNavigation.openService(
                  context,
                  preselectedMaintenanceItemId: reminder.item.id,
                );
                await onRefresh();
              },
              icon: const Icon(Icons.build_circle_outlined),
              label: const Text('Record'),
            ),
            onTap: () async {
              await AppNavigation.openMaintenanceItemDetails(
                context,
                reminder.item.id,
              );
              await onRefresh();
            },
          ),
      ],
    );
  }
}

String _reminderSubtitle(MaintenanceReminder reminder, Vehicle vehicle) {
  final parts = <String>[
    reminder.state.label,
    if (reminder.nextMileageDue != null)
      'Due at ${DTFormatters.odometer(reminder.nextMileageDue, vehicle.distanceUnit)}',
    if (reminder.nextDateDue != null) DTFormatters.date(reminder.nextDateDue!),
    _remainingText(reminder, vehicle),
  ];
  return parts.where((part) => part.trim().isNotEmpty).join(' / ');
}

String _remainingText(MaintenanceReminder reminder, Vehicle vehicle) {
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
    return 'Add a baseline or service';
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
