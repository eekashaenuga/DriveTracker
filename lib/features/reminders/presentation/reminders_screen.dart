import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/utilities/formatters.dart';
import '../../../shared/widgets/dt_date_field.dart';
import '../../../shared/widgets/dt_empty_state.dart';
import '../../../shared/widgets/dt_list_card.dart';
import '../../../shared/widgets/dt_section_header.dart';
import '../../../shared/widgets/dt_status_badge.dart';
import '../../documents/domain/vehicle_document.dart';
import '../../maintenance/domain/maintenance_reminder.dart';
import '../../vehicles/domain/vehicle.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  Future<_ReminderBundle>? _remindersFuture;
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
      _remindersFuture = _loadReminders(controller);
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
              FutureBuilder<_ReminderBundle>(
                future: _remindersFuture,
                builder: (context, snapshot) {
                  final bundle = snapshot.data;
                  if (bundle == null) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: DTSpacing.xl),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final visible = bundle.maintenance
                      .where((reminder) => reminder.shouldShowAsReminder)
                      .toList();
                  final visibleDocuments = bundle.documents
                      .where((reminder) => reminder.shouldShowAsReminder)
                      .toList();
                  if (visible.isEmpty && visibleDocuments.isEmpty) {
                    return const DTEmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: 'No active reminders',
                      body: 'Add maintenance intervals or document expiry dates to track upcoming work.',
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
                  final documentAttention = visibleDocuments
                      .where(
                        (reminder) =>
                            reminder.state.severity >=
                            MaintenanceReminderState.dueSoon.severity,
                      )
                      .toList();
                  final documentUpcoming = visibleDocuments
                      .where(
                        (reminder) =>
                            reminder.state == MaintenanceReminderState.upcoming,
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
                      _DocumentReminderSection(
                        title: 'Document attention',
                        reminders: documentAttention,
                        onRefresh: _refresh,
                      ),
                      _ReminderSection(
                        title: 'Upcoming',
                        reminders: upcoming,
                        vehicle: vehicle,
                        onRefresh: _refresh,
                      ),
                      _DocumentReminderSection(
                        title: 'Upcoming documents',
                        reminders: documentUpcoming,
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
    final future = _loadReminders(controller);
    setState(() {
      _remindersFuture = future;
    });
    await future;
  }

  Future<_ReminderBundle> _loadReminders(
    DriveTrackerController controller,
  ) async {
    final maintenance = await controller
        .maintenanceRemindersForSelectedVehicle();
    final documents = await controller.documentRemindersForSelectedVehicle();
    return _ReminderBundle(maintenance: maintenance, documents: documents);
  }
}

class _ReminderBundle {
  const _ReminderBundle({required this.maintenance, required this.documents});

  final List<MaintenanceReminder> maintenance;
  final List<DocumentExpiryReminder> documents;
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
          Padding(
            key: Key('reminder_${reminder.item.id}'),
            padding: const EdgeInsets.only(bottom: DTSpacing.sm),
            child: DTListCard(
              icon: _iconForState(reminder.state),
              title: reminder.item.name,
              subtitle: _reminderSubtitle(reminder, vehicle),
              accentColor: _colorForState(context, reminder.state),
              trailing: _ReminderAction(
                state: reminder.state,
                actionKey: Key('recordService_${reminder.item.id}'),
                icon: Icons.build_circle_outlined,
                label: 'Record',
                onPressed: () async {
                  await AppNavigation.openService(
                    context,
                    preselectedMaintenanceItemId: reminder.item.id,
                  );
                  await onRefresh();
                },
              ),
              onTap: () async {
                await AppNavigation.openMaintenanceItemDetails(
                  context,
                  reminder.item.id,
                );
                await onRefresh();
              },
            ),
          ),
      ],
    );
  }
}

class _DocumentReminderSection extends StatelessWidget {
  const _DocumentReminderSection({
    required this.title,
    required this.reminders,
    required this.onRefresh,
  });

  final String title;
  final List<DocumentExpiryReminder> reminders;
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
          Padding(
            key: Key('documentReminder_${reminder.document.id}'),
            padding: const EdgeInsets.only(bottom: DTSpacing.sm),
            child: DTListCard(
              icon: _iconForState(reminder.state),
              title: reminder.title,
              subtitle: _documentReminderSubtitle(reminder),
              accentColor: _colorForState(context, reminder.state),
              trailing: _ReminderAction(
                state: reminder.state,
                actionKey: Key('openDocumentReminder_${reminder.document.id}'),
                icon: Icons.description_outlined,
                label: 'Open',
                onPressed: () async {
                  await AppNavigation.openDocumentDetails(
                    context,
                    reminder.document.id,
                  );
                  await onRefresh();
                },
              ),
              onTap: () async {
                await AppNavigation.openDocumentDetails(
                  context,
                  reminder.document.id,
                );
                await onRefresh();
              },
            ),
          ),
      ],
    );
  }
}

class _ReminderAction extends StatelessWidget {
  const _ReminderAction({
    required this.state,
    required this.actionKey,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final MaintenanceReminderState state;
  final Key actionKey;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = _colorForState(context, state);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        DTStatusBadge(
          label: state.label,
          color: color,
          icon: _iconForState(state),
          compact: true,
        ),
        const SizedBox(height: DTSpacing.xs),
        TextButton.icon(
          key: actionKey,
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
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

String _documentReminderSubtitle(DocumentExpiryReminder reminder) {
  final expiry = reminder.document.expiryDate;
  final parts = <String>[
    reminder.state.label,
    if (expiry != null) 'Recorded expiry: ${compactDate(expiry)}',
    _documentRemainingText(reminder.daysRemaining),
  ];
  return parts.where((part) => part.trim().isNotEmpty).join(' / ');
}

String _documentRemainingText(int days) {
  if (days < 0) {
    return 'Expired ${-days} days ago';
  }
  if (days == 0) {
    return 'Expires today';
  }
  if (days == 1) {
    return 'Expires tomorrow';
  }
  return 'Expires in $days days';
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
