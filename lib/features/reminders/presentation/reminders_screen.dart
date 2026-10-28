import 'notification_health_panel.dart';
import '../domain/reminder_overview.dart';

import 'package:flutter/material.dart';

import '../../documents/domain/document_type.dart';

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

enum ReminderTypeFilter { all, maintenance, documents }

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({this.initialVehicleId, super.key});
  final String? initialVehicleId;
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  static const _all = '__all__';
  Future<_ReminderBundle>? _remindersFuture;
  String? _scope, _signature;
  bool _localScope = false;
  ReminderTypeFilter _type = ReminderTypeFilter.all;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriveTrackerController>();
    final vehicles = c.activeVehicles;
    _scope ??= widget.initialVehicleId ?? c.selectedVehicle?.id ?? _all;
    if (!_localScope && widget.initialVehicleId == null) {
      _scope = c.selectedVehicle?.id ?? _all;
    }
    if (_scope != _all && !vehicles.any((v) => v.id == _scope)) _scope = _all;
    if (vehicles.isEmpty) {
      return const Scaffold(
        body: SafeArea(
          child: DTEmptyState(
            icon: Icons.notifications_none_rounded,
            title: 'No active vehicle',
            body: 'Add or restore a vehicle before reviewing reminders.',
          ),
        ),
      );
    }
    final ids = vehicles
        .where((v) => _scope == _all || v.id == _scope)
        .map((v) => v.id)
        .toList();
    final signature = '$_scope:${c.dataRevision}';
    if (_remindersFuture == null || signature != _signature) {
      _signature = signature;
      _remindersFuture = _loadReminders(c, ids);
    }
    Vehicle vehicleFor(ReminderOverviewEntry e) =>
        vehicles.firstWhere((v) => v.id == e.vehicleId);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            key: const Key('remindersList'),
            physics: const AlwaysScrollableScrollPhysics(),
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
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('remindersVehicle_$_scope'),
                initialValue: _scope,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Vehicle'),
                items: [
                  const DropdownMenuItem(
                    value: _all,
                    child: Text('All active vehicles'),
                  ),
                  for (final v in vehicles)
                    DropdownMenuItem(
                      value: v.id,
                      child: Text(v.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _scope = value;
                  _localScope = true;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ReminderTypeFilter>(
                key: ValueKey('remindersTypeFilter_${_type.name}'),
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Reminder type'),
                items: [
                  const DropdownMenuItem(
                    value: ReminderTypeFilter.all,
                    child: Text('All'),
                  ),
                  const DropdownMenuItem(
                    value: ReminderTypeFilter.maintenance,
                    child: Text('Maintenance'),
                  ),
                  const DropdownMenuItem(
                    value: ReminderTypeFilter.documents,
                    child: Text('Documents'),
                  ),
                ],
                onChanged: (value) => setState(() => _type = value!),
              ),
              NotificationHealthPanel(),
              FutureBuilder<_ReminderBundle>(
                key: ValueKey(_scope),
                future: _remindersFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Column(
                      children: [
                        const DTEmptyState(
                          icon: Icons.error_outline,
                          title: 'Could not load reminders',
                          body: 'Your records are unchanged. Retry loading reminders.',
                        ),
                        TextButton(
                          onPressed: _refresh,
                          child: const Text('Retry'),
                        ),
                      ],
                    );
                  }
                  final bundle = snapshot.data;
                  if (snapshot.connectionState != ConnectionState.done ||
                      bundle == null) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final ordered = orderReminderOverview(
                    bundle.maintenance,
                    bundle.documents,
                  );
                  final filtered = ordered.where((entry) {
                    final sources = entry.isMotReview
                        ? entry.motSources
                        : [entry];
                    return _type == ReminderTypeFilter.all ||
                        sources.any(
                          (s) => _type == ReminderTypeFilter.maintenance
                              ? s.maintenance != null
                              : s.document != null,
                        );
                  }).toList();
                  if (ordered.isEmpty) {
                    return const DTEmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: 'No active reminders',
                      body: 'No configured reminders for these vehicles. Add maintenance intervals or document dates; Android notifications are separate.',
                    );
                  }
                  if (filtered.isEmpty) {
                    return Column(
                      children: [
                        const DTEmptyState(
                          icon: Icons.filter_list,
                          title: 'No reminders match these filters',
                          body:
                              'Other reminder types may still need attention.',
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => _type = ReminderTypeFilter.all),
                          child: const Text('Show all types'),
                        ),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < filtered.length; i++) ...[
                        if (i == 0 ||
                            filtered[i].sectionTitle !=
                                filtered[i - 1].sectionTitle)
                          DTSectionHeader(title: filtered[i].sectionTitle),
                        if (filtered[i].isMotReview)
                          _MotSourcesReminder(
                            entry: filtered[i],
                            vehicle: vehicleFor(filtered[i]),
                            onRefresh: _refresh,
                          )
                        else if (filtered[i].maintenance != null)
                          _ReminderSection(
                            title: '',
                            reminders: [filtered[i].maintenance!],
                            vehicle: vehicleFor(filtered[i]),
                            showVehicle: _scope == _all,
                            onRefresh: _refresh,
                          )
                        else
                          _DocumentReminderSection(
                            title: '',
                            reminders: [filtered[i].document!],
                            vehicleName: _scope == _all
                                ? vehicleFor(filtered[i]).name
                                : null,
                            onRefresh: _refresh,
                          ),
                      ],
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
    if (!mounted) return;
    final c = context.read<DriveTrackerController>();
    final ids = c.activeVehicles
        .where((v) => _scope == _all || v.id == _scope)
        .map((v) => v.id)
        .toList();
    final future = _loadReminders(c, ids);
    setState(() {
      _remindersFuture = future;
    });
    try {
      await future;
    } catch (_) {
      /* FutureBuilder owns the retry state. */
    }
  }

  Future<_ReminderBundle> _loadReminders(
    DriveTrackerController c,
    List<String> ids,
  ) async {
    final maintenance = <MaintenanceReminder>[];
    final documents = <DocumentExpiryReminder>[];
    for (final id in ids) {
      maintenance.addAll(await c.maintenanceRemindersForVehicle(id));
      documents.addAll(await c.documentRemindersForVehicle(id));
    }
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
    this.showVehicle = false,
    required this.title,
    required this.reminders,
    required this.vehicle,
    required this.onRefresh,
  });

  final bool showVehicle;
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
        if (title.isNotEmpty) DTSectionHeader(title: title),
        for (final reminder in reminders)
          Padding(
            key: Key('reminder_${reminder.item.id}'),
            padding: const EdgeInsets.only(bottom: DTSpacing.sm),
            child: DTListCard(
              icon: _iconForState(reminder.state),
              title: reminder.item.name,
              subtitle:
                  '${showVehicle ? '${vehicle.name} · ' : ''}${_reminderSubtitle(reminder, vehicle)}',
              subtitleMaxLines: null,
              stackTrailingOnNarrow: true,
              accentColor: _colorForState(context, reminder.state),
              trailing: _ReminderAction(
                state: reminder.state,
                actionKey: Key('recordService_${reminder.item.id}'),
                icon: reminder.item.isExpiry
                    ? Icons.event_repeat
                    : Icons.build_circle_outlined,
                label: reminder.state == MaintenanceReminderState.setupNeeded
                    ? 'Set up'
                    : reminder.item.isExpiry
                    ? 'Renew'
                    : 'Record',
                onPressed: () async {
                  if (reminder.state == MaintenanceReminderState.setupNeeded) {
                    await AppNavigation.openMaintenanceItemDetails(
                      context,
                      reminder.item.id,
                    );
                  } else if (reminder.item.isExpiry) {
                    await AppNavigation.openEditMaintenanceItem(
                      context,
                      reminder.item,
                    );
                  } else {
                    await AppNavigation.openService(
                      context,
                      preselectedMaintenanceItemId: reminder.item.id,
                    );
                  }
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
    this.vehicleName,
    required this.title,
    required this.reminders,
    required this.onRefresh,
  });

  final String? vehicleName;
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
        if (title.isNotEmpty) DTSectionHeader(title: title),
        for (final reminder in reminders)
          Padding(
            key: Key('documentReminder_${reminder.document.id}'),
            padding: const EdgeInsets.only(bottom: DTSpacing.sm),
            child: DTListCard(
              icon: _iconForState(_documentDisplayState(reminder)),
              title: reminder.title,
              subtitle:
                  '${vehicleName == null ? '' : '$vehicleName · '}${_documentReminderSubtitle(reminder)}',
              subtitleMaxLines: null,
              stackTrailingOnNarrow: true,
              accentColor: _colorForState(
                context,
                _documentDisplayState(reminder),
              ),
              trailing: _ReminderAction(
                state: _documentDisplayState(reminder),
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

class _MotSourcesReminder extends StatelessWidget {
  const _MotSourcesReminder({
    required this.entry,
    required this.vehicle,
    required this.onRefresh,
  });
  final ReminderOverviewEntry entry;
  final Vehicle vehicle;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final sources = entry.motSources.map((source) {
      final document = source.document?.document;
      final maintenance = source.maintenance;
      final date = document?.expiryDate ?? maintenance?.nextDateDue;
      final label = document != null
          ? 'Document: ${document.title}'
          : 'Maintenance: ${maintenance!.item.name}';
      final basis = document != null || maintenance!.item.isExpiry
          ? 'expires'
          : 'due';
      return '$label - $basis ${date == null ? 'not recorded' : compactDate(date)}';
    });
    return Padding(
      key: Key('motReminderSources_${vehicle.id}'),
      padding: const EdgeInsets.only(bottom: DTSpacing.sm),
      child: DTListCard(
        icon: Icons.warning_amber_rounded,
        title: entry.name,
        subtitle: [
          '${vehicle.name} · ${entry.state == MaintenanceReminderState.overdue ? 'Overdue · ' : ''}Multiple active MOT sources. Review the user-recorded dates and notification timings.',
          ...sources,
        ].join('\n'),
        subtitleMaxLines: null,
        accentColor: Theme.of(context).colorScheme.tertiary,
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await AppNavigation.openDocuments(context, vehicleId: vehicle.id);
          await onRefresh();
        },
      ),
    );
  }
}

MaintenanceReminderState _documentDisplayState(
  DocumentExpiryReminder reminder,
) => reminder.state == MaintenanceReminderState.normal
    ? MaintenanceReminderState.upcoming
    : reminder.state;

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
    reminder.item.isExpiry ? 'Expiry reminder' : reminder.state.label,
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
    if (expiry != null)
      '${reminder.document.type == DocumentType.tax ? 'Due' : 'Expires'} ${compactDate(expiry)}',
    'User-recorded',
    _documentRemainingText(
      reminder.daysRemaining,
      tax: reminder.document.type == DocumentType.tax,
    ),
  ];
  return parts.where((part) => part.trim().isNotEmpty).join(' / ');
}

String _documentRemainingText(int days, {bool tax = false}) {
  if (tax) {
    if (days < 0) return 'Overdue by ${-days} days';
    if (days == 0) return 'Due today';
    return 'Due in $days days';
  }
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
    MaintenanceReminderState.setupNeeded => Icons.tune_rounded,
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
    MaintenanceReminderState.setupNeeded => colors.onSurfaceVariant,
    MaintenanceReminderState.normal => colors.onSurfaceVariant,
  };
}
