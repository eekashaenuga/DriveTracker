import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../../shared/widgets/dt_empty_state.dart';
import '../../../shared/widgets/dt_list_card.dart';
import '../../../shared/widgets/dt_section_header.dart';
import '../../vehicles/domain/vehicle.dart';

class VehicleUnitsScreen extends StatelessWidget {
  const VehicleUnitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    final activeVehicles = controller.activeVehicles;
    final archivedVehicles = controller.archivedVehicles;
    final hasVehicles =
        activeVehicles.isNotEmpty || archivedVehicles.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle units')),
      body: SafeArea(
        child: ListView(
          key: const Key('vehicleUnitsScreen'),
          padding: const EdgeInsets.fromLTRB(
            DTSpacing.lg,
            DTSpacing.sm,
            DTSpacing.lg,
            DTSpacing.xxxl,
          ),
          children: [
            if (!hasVehicles)
              const DTEmptyState(
                icon: Icons.straighten_rounded,
                title: 'No vehicles yet',
                body: 'Add a vehicle before choosing distance units.',
              )
            else ...[
              if (activeVehicles.isNotEmpty) ...[
                const DTSectionHeader(title: 'Active vehicles'),
                for (final vehicle in activeVehicles) ...[
                  _VehicleUnitTile(vehicle: vehicle),
                  const SizedBox(height: DTSpacing.sm),
                ],
              ],
              if (archivedVehicles.isNotEmpty) ...[
                const DTSectionHeader(title: 'Archived vehicles'),
                for (final vehicle in archivedVehicles) ...[
                  _VehicleUnitTile(vehicle: vehicle),
                  const SizedBox(height: DTSpacing.sm),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _VehicleUnitTile extends StatelessWidget {
  const _VehicleUnitTile({required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    final unitLabel = _unitLabel(vehicle.distanceUnit);

    return DTListCard(
      key: Key('vehicleUnitTile_${vehicle.id}'),
      icon: Icons.directions_car_rounded,
      title: vehicle.name,
      subtitle: '${vehicle.description} · Current: $unitLabel',
      accentColor: DTAccents.odometer(context),
      enabled: !controller.isBusy,
      onTap: () => _showUnitSheet(context),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            vehicle.distanceUnit.shortLabel,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: DTSpacing.xs),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
      semanticLabel: '${vehicle.name}, $unitLabel',
    );
  }

  Future<void> _showUnitSheet(BuildContext context) async {
    final selected = await showModalBottomSheet<DistanceUnit>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            DTSpacing.lg,
            DTSpacing.sm,
            DTSpacing.lg,
            DTSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                vehicle.name,
                style: Theme.of(sheetContext).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: DTSpacing.md),
              RadioGroup<DistanceUnit>(
                groupValue: vehicle.distanceUnit,
                onChanged: (value) => Navigator.of(sheetContext).pop(value),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final unit in DistanceUnit.values)
                      RadioListTile<DistanceUnit>(
                        key: Key(
                          'vehicleUnitOption_${vehicle.id}_${unit.name}',
                        ),
                        value: unit,
                        title: Text(_unitLabel(unit)),
                        secondary: const Icon(Icons.straighten_rounded),
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!context.mounted ||
        selected == null ||
        selected == vehicle.distanceUnit) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change distance unit?'),
        content: Text(
          'Existing mileage records for ${vehicle.name} will be converted from '
          '${_unitLabel(vehicle.distanceUnit)} to ${_unitLabel(selected)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Change unit'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      await context.read<DriveTrackerController>().updateVehicleDistanceUnit(
        vehicle.id,
        selected,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${vehicle.name} units updated.')),
        );
      }
    } on ValidationException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  String _unitLabel(DistanceUnit unit) {
    return switch (unit) {
      DistanceUnit.miles => 'Miles (mi)',
      DistanceUnit.kilometers => 'Kilometres (km)',
    };
  }
}
