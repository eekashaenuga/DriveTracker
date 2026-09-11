import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/utilities/money.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../../shared/widgets/dt_activity_row.dart';
import '../../../shared/widgets/dt_metric_card.dart';
import '../../../shared/widgets/dt_section_header.dart';
import '../../odometer/domain/odometer_entry.dart';
import '../domain/vehicle.dart';

class VehicleDetailsScreen extends StatelessWidget {
  const VehicleDetailsScreen({required this.vehicleId, super.key});

  final String vehicleId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    final vehicle = _findVehicle(controller);

    if (vehicle == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Vehicle')),
        body: const Center(child: Text('Vehicle not found.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(vehicle.name),
        actions: [
          IconButton(
            tooltip: 'Edit vehicle',
            onPressed: () => AppNavigation.openEditVehicle(context, vehicle),
            icon: const Icon(Icons.edit_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<_VehicleDetailsData>(
          future: _loadDetails(controller, vehicle),
          builder: (context, snapshot) {
            final currentOdometer = snapshot.data?.currentOdometer;
            final entries = snapshot.data?.entries ?? const [];

            return ListView(
              padding: const EdgeInsets.fromLTRB(
                DTSpacing.lg,
                DTSpacing.sm,
                DTSpacing.lg,
                DTSpacing.xxxl,
              ),
              children: [
                Text(
                  vehicle.description,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: DTSpacing.xs),
                Text(
                  vehicle.registrationLabel,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: DTSpacing.xl),
                DTMetricCard(
                  icon: Icons.speed_rounded,
                  label: 'Current odometer',
                  value: DTFormatters.odometer(
                    currentOdometer,
                    vehicle.distanceUnit,
                  ),
                  supportingText: 'Derived from highest valid saved reading',
                ),
                const DTSectionHeader(title: 'Profile'),
                _ProfileRows(vehicle: vehicle),
                const DTSectionHeader(title: 'Odometer history'),
                if (entries.isEmpty)
                  const Text('No odometer entries recorded yet.')
                else
                  for (final entry in entries)
                    DTActivityRow(
                      icon: Icons.speed_rounded,
                      title: '${entry.sourceType.label} reading',
                      subtitle: DTFormatters.dateTime(entry.eventDateTime),
                      trailing: Text(
                        DTFormatters.odometer(
                          entry.odometer,
                          vehicle.distanceUnit,
                        ),
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                if (vehicle.isArchived) ...[
                  const SizedBox(height: DTSpacing.xl),
                  FilledButton.icon(
                    key: const Key('restoreVehicleDetailsButton'),
                    onPressed: () => _restoreVehicle(context, vehicle),
                    icon: const Icon(Icons.unarchive_outlined),
                    label: const Text('Restore vehicle'),
                  ),
                ] else ...[
                  const SizedBox(height: DTSpacing.xl),
                  OutlinedButton.icon(
                    onPressed: () => _confirmArchive(context, vehicle),
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('Archive vehicle'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Vehicle? _findVehicle(DriveTrackerController controller) {
    for (final vehicle in [
      ...controller.activeVehicles,
      ...controller.archivedVehicles,
    ]) {
      if (vehicle.id == vehicleId) {
        return vehicle;
      }
    }
    return null;
  }

  Future<_VehicleDetailsData> _loadDetails(
    DriveTrackerController controller,
    Vehicle vehicle,
  ) async {
    final currentOdometer = await controller.currentOdometerForVehicle(
      vehicle.id,
    );
    final entries = await controller.odometerEntriesForVehicle(vehicle.id);
    return _VehicleDetailsData(
      currentOdometer: currentOdometer,
      entries: entries,
    );
  }

  Future<void> _confirmArchive(BuildContext context, Vehicle vehicle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Archive ${vehicle.name}?'),
        content: const Text(
          'This keeps vehicle records and odometer history, but removes the vehicle from normal selection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      await context.read<DriveTrackerController>().archiveVehicle(vehicle.id);
      if (context.mounted) {
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(content: Text('${vehicle.name} archived.')),
        );
      }
    } on ValidationException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _restoreVehicle(BuildContext context, Vehicle vehicle) async {
    try {
      await context.read<DriveTrackerController>().restoreVehicle(vehicle.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${vehicle.name} restored.')));
      }
    } on ValidationException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _ProfileRows extends StatelessWidget {
  const _ProfileRows({required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final rows = <_ProfileRowData>[
      _ProfileRowData('Fuel type', vehicle.fuelType.label),
      _ProfileRowData('Distance unit', vehicle.distanceUnit.label),
      if (vehicle.trim != null) _ProfileRowData('Trim', vehicle.trim!),
      if (vehicle.engine != null) _ProfileRowData('Engine', vehicle.engine!),
      if (vehicle.transmission != null)
        _ProfileRowData('Transmission', vehicle.transmission!),
      if (vehicle.vin != null) _ProfileRowData('VIN', vehicle.vin!),
      if (vehicle.colour != null) _ProfileRowData('Colour', vehicle.colour!),
      if (vehicle.purchaseDate != null)
        _ProfileRowData(
          'Purchase date',
          DTFormatters.date(vehicle.purchaseDate!),
        ),
      if (vehicle.purchaseMileage != null)
        _ProfileRowData(
          'Purchase mileage',
          DTFormatters.odometer(vehicle.purchaseMileage, vehicle.distanceUnit),
        ),
      if (vehicle.purchasePrice != null)
        _ProfileRowData(
          'Purchase price',
          '${MoneyAmount.defaultCurrency.symbol}${vehicle.purchasePrice!.toStringAsFixed(2)}',
        ),
      if (vehicle.seller != null) _ProfileRowData('Seller', vehicle.seller!),
      if (vehicle.notes != null) _ProfileRowData('Notes', vehicle.notes!),
      if (vehicle.isArchived) _ProfileRowData('Status', 'Archived'),
    ];

    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DTSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 128,
                  child: Text(
                    row.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.value,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ProfileRowData {
  const _ProfileRowData(this.label, this.value);

  final String label;
  final String value;
}

class _VehicleDetailsData {
  const _VehicleDetailsData({
    required this.currentOdometer,
    required this.entries,
  });

  final int? currentOdometer;
  final List<OdometerEntry> entries;
}
