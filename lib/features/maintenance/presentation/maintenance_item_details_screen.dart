import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/utilities/formatters.dart';
import '../../../shared/widgets/dt_empty_state.dart';
import '../../../shared/widgets/dt_primary_button.dart';
import '../../../shared/widgets/dt_section_header.dart';
import '../../vehicles/domain/vehicle.dart';
import '../domain/maintenance_item.dart';
import '../domain/maintenance_reminder.dart';
import '../domain/service_record.dart';

class MaintenanceItemDetailsScreen extends StatefulWidget {
  const MaintenanceItemDetailsScreen({required this.itemId, super.key});

  final String itemId;

  @override
  State<MaintenanceItemDetailsScreen> createState() =>
      _MaintenanceItemDetailsScreenState();
}

class _MaintenanceItemDetailsScreenState
    extends State<MaintenanceItemDetailsScreen> {
  Future<_MaintenanceItemDetailData?>? _detailFuture;
  String? _loadedVehicleId;

  @override
  Widget build(BuildContext context) {
    final selectedVehicleId = context
        .watch<DriveTrackerController>()
        .selectedVehicle
        ?.id;
    if (_detailFuture == null || _loadedVehicleId != selectedVehicleId) {
      _loadedVehicleId = selectedVehicleId;
      _detailFuture = _load();
    }
    return FutureBuilder<_MaintenanceItemDetailData?>(
      future: _detailFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              appBar: _DetailsAppBar(title: 'Maintenance'),
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return const Scaffold(
            appBar: _DetailsAppBar(title: 'Maintenance'),
            body: DTEmptyState(
              icon: Icons.handyman_rounded,
              title: 'Maintenance item not found',
              body: 'This maintenance item is no longer available.',
            ),
          );
        }

        return Scaffold(
          appBar: _DetailsAppBar(title: data.item.name),
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
                  data.reminder.state.label,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: DTSpacing.sm),
                Text(_summary(data.reminder, data.vehicle)),
                const SizedBox(height: DTSpacing.lg),
                DTPrimaryButton(
                  key: const Key('maintenanceDetailRecordServiceButton'),
                  label: 'Record service',
                  icon: Icons.build_circle_outlined,
                  onPressed: () async {
                    await AppNavigation.openService(
                      context,
                      preselectedMaintenanceItemId: data.item.id,
                    );
                    if (mounted) {
                      _refresh();
                    }
                  },
                ),
                const SizedBox(height: DTSpacing.md),
                OutlinedButton.icon(
                  key: const Key('editMaintenanceItemButton'),
                  onPressed: () async {
                    await AppNavigation.openEditMaintenanceItem(
                      context,
                      data.item,
                    );
                    if (mounted) {
                      _refresh();
                    }
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit item'),
                ),
                const SizedBox(height: DTSpacing.md),
                OutlinedButton.icon(
                  key: const Key('archiveMaintenanceItemButton'),
                  onPressed: data.item.isArchived ? null : _archive,
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('Archive item'),
                ),
                const DTSectionHeader(title: 'Definition'),
                _DefinitionRows(item: data.item, vehicle: data.vehicle),
                const DTSectionHeader(title: 'History'),
                if (data.history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: DTSpacing.lg),
                    child: Text('No services have completed this item yet.'),
                  )
                else
                  for (final completion in data.history)
                    ListTile(
                      key: Key('maintenanceHistory_${completion.serviceId}'),
                      leading: Icon(
                        completion.isBaseline
                            ? Icons.flag_outlined
                            : Icons.build_circle_outlined,
                      ),
                      title: Text(
                        completion.isBaseline
                            ? 'Baseline completion'
                            : completion.itemName,
                      ),
                      subtitle: Text(
                        _historySubtitle(completion, data.vehicle),
                      ),
                      trailing: completion.isBaseline
                          ? null
                          : Text(
                              DTFormatters.moneyMinor(
                                completion.totalCostMinor,
                              ),
                            ),
                      onTap: () async {
                        final controller = context
                            .read<DriveTrackerController>();
                        final service = await controller.serviceRecordById(
                          completion.serviceId,
                        );
                        if (service == null) {
                          return;
                        }
                        if (!context.mounted) {
                          return;
                        }
                        await AppNavigation.openService(
                          context,
                          service: service,
                        );
                        if (!context.mounted) {
                          return;
                        }
                        _refresh();
                      },
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<_MaintenanceItemDetailData?> _load() async {
    final controller = context.read<DriveTrackerController>();
    final item = await controller.maintenanceItemById(widget.itemId);
    final selectedVehicle = controller.selectedVehicle;
    if (item == null || selectedVehicle == null) {
      return null;
    }
    if (item.vehicleId != selectedVehicle.id) {
      return null;
    }
    final vehicle = selectedVehicle;
    final reminder = await controller.maintenanceReminderForItem(item);
    final history = await controller.maintenanceHistoryForItem(item);
    if (reminder == null) {
      return null;
    }
    return _MaintenanceItemDetailData(
      item: item,
      vehicle: vehicle,
      reminder: reminder,
      history: history,
    );
  }

  void _refresh() {
    setState(() {
      _detailFuture = _load();
    });
  }

  Future<void> _archive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive item?'),
        content: const Text(
          'Service history is preserved, but the item is removed from active reminders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirmArchiveMaintenanceItemButton'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await context.read<DriveTrackerController>().archiveMaintenanceItem(
      widget.itemId,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Maintenance archived.')));
  }
}

class _MaintenanceItemDetailData {
  const _MaintenanceItemDetailData({
    required this.item,
    required this.vehicle,
    required this.reminder,
    required this.history,
  });

  final MaintenanceItem item;
  final Vehicle vehicle;
  final MaintenanceReminder reminder;
  final List<MaintenanceCompletion> history;
}

class _DetailsAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _DetailsAppBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return AppBar(title: Text(title));
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _DefinitionRows extends StatelessWidget {
  const _DefinitionRows({required this.item, required this.vehicle});

  final MaintenanceItem item;
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _InfoRow(label: 'Category', value: item.category ?? '-'),
        _InfoRow(
          label: 'Mileage interval',
          value: item.mileageInterval == null
              ? '-'
              : DTFormatters.odometer(
                  item.mileageInterval,
                  vehicle.distanceUnit,
                ),
        ),
        _InfoRow(
          label: 'Time interval',
          value: item.timeIntervalDays == null
              ? '-'
              : '${item.timeIntervalDays} days',
        ),
        _InfoRow(label: 'Reminder', value: item.reminderEnabled ? 'On' : 'Off'),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

String _summary(MaintenanceReminder reminder, Vehicle vehicle) {
  final parts = <String>[
    if (reminder.nextMileageDue != null)
      'Next ${DTFormatters.odometer(reminder.nextMileageDue, vehicle.distanceUnit)}',
    if (reminder.nextDateDue != null)
      'Next ${DTFormatters.date(reminder.nextDateDue!)}',
    _remainingText(reminder, vehicle),
  ];
  return parts.where((part) => part.trim().isNotEmpty).join(' / ');
}

String _remainingText(MaintenanceReminder reminder, Vehicle vehicle) {
  if (reminder.primaryBasis == MaintenanceReminderBasis.mileage &&
      reminder.milesRemaining != null) {
    final miles = reminder.milesRemaining!;
    if (miles < 0) {
      return 'Overdue by ${DTFormatters.odometer(-miles, vehicle.distanceUnit)}';
    }
    if (miles == 0) {
      return 'Due now';
    }
    return '${DTFormatters.odometer(miles, vehicle.distanceUnit)} remaining';
  }
  final days = reminder.daysRemaining;
  if (days == null) {
    return reminder.item.hasInterval && reminder.item.reminderEnabled
        ? 'Add a baseline or service'
        : 'No active reminder';
  }
  if (days < 0) {
    return 'Overdue by ${-days} days';
  }
  if (days == 0) {
    return 'Due today';
  }
  return 'Due in $days days';
}

String _historySubtitle(MaintenanceCompletion completion, Vehicle vehicle) {
  final parts = <String>[
    DTFormatters.dateTime(completion.eventDateTime),
    if (completion.odometer != null)
      DTFormatters.odometer(completion.odometer, vehicle.distanceUnit),
    if (completion.garage != null) completion.garage!,
  ];
  return parts.where((part) => part.trim().isNotEmpty).join(' / ');
}
