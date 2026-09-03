import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../../shared/widgets/dt_empty_state.dart';
import '../../../shared/widgets/dt_primary_button.dart';
import '../../../shared/widgets/dt_section_header.dart';
import '../../../shared/widgets/dt_vehicle_card.dart';
import '../domain/vehicle.dart';

enum _VehicleAction { edit, archive }

class VehiclesScreen extends StatelessWidget {
  const VehiclesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    final selectedId = controller.selectedVehicle?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicles'),
        actions: [
          IconButton(
            tooltip: 'Add vehicle',
            onPressed: () => AppNavigation.openAddVehicle(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            DTSpacing.lg,
            DTSpacing.sm,
            DTSpacing.lg,
            DTSpacing.xxxl,
          ),
          children: [
            const DTSectionHeader(title: 'Active vehicles'),
            if (controller.activeVehicles.isEmpty)
              DTEmptyState(
                icon: Icons.directions_car_rounded,
                title: 'No active vehicles',
                body: 'Archived vehicles are preserved. Add a vehicle to track mileage again.',
                action: DTPrimaryButton(
                  label: 'Add vehicle',
                  icon: Icons.add_rounded,
                  onPressed: () => AppNavigation.openAddVehicle(context),
                ),
              )
            else
              for (final vehicle in controller.activeVehicles) ...[
                FutureBuilder<int?>(
                  future: controller.currentOdometerForVehicle(vehicle.id),
                  builder: (context, snapshot) {
                    final label = snapshot.hasData
                        ? DTFormatters.odometer(
                            snapshot.data,
                            vehicle.distanceUnit,
                          )
                        : vehicle.registrationLabel;
                    return DTVehicleCard(
                      vehicle: vehicle,
                      currentOdometerLabel: label,
                      isSelected: vehicle.id == selectedId,
                      onTap: () =>
                          AppNavigation.openVehicleDetails(context, vehicle),
                      trailing: PopupMenuButton<_VehicleAction>(
                        tooltip: 'Vehicle actions',
                        onSelected: (action) =>
                            _handleAction(context, vehicle, action),
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: _VehicleAction.edit,
                            child: Text('Edit'),
                          ),
                          PopupMenuItem(
                            value: _VehicleAction.archive,
                            child: Text('Archive'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: DTSpacing.sm),
              ],
            if (controller.archivedVehicles.isNotEmpty) ...[
              const DTSectionHeader(title: 'Archived'),
              for (final vehicle in controller.archivedVehicles) ...[
                DTVehicleCard(
                  vehicle: vehicle,
                  onTap: () =>
                      AppNavigation.openVehicleDetails(context, vehicle),
                  trailing: const Icon(Icons.archive_outlined),
                ),
                const SizedBox(height: DTSpacing.sm),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    Vehicle vehicle,
    _VehicleAction action,
  ) async {
    switch (action) {
      case _VehicleAction.edit:
        await AppNavigation.openEditVehicle(context, vehicle);
        break;
      case _VehicleAction.archive:
        await _confirmArchive(context, vehicle);
        break;
    }
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
      await context.read<DriveTrackerController>().archiveVehicle(vehicle.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${vehicle.name} archived.')));
      }
    } on ValidationException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}
