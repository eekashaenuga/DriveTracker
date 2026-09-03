import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../shared/widgets/dt_empty_state.dart';
import '../../../shared/widgets/dt_primary_button.dart';
import '../../../shared/widgets/dt_vehicle_card.dart';
import '../../../shared/widgets/dt_bottom_sheet.dart';

Future<void> showVehicleSelectorSheet(BuildContext context) {
  return showDTBottomSheet<void>(
    context: context,
    builder: (sheetContext) => VehicleSelectorSheet(parentContext: context),
  );
}

class VehicleSelectorSheet extends StatelessWidget {
  const VehicleSelectorSheet({required this.parentContext, super.key});

  final BuildContext parentContext;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    final selectedId = controller.selectedVehicle?.id;

    return Padding(
      padding: EdgeInsets.only(
        left: DTSpacing.lg,
        right: DTSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + DTSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select vehicle',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: DTSpacing.md),
          if (controller.activeVehicles.isEmpty)
            DTEmptyState(
              icon: Icons.directions_car_rounded,
              title: 'No active vehicles',
              body: 'Add a vehicle to make it available on Home.',
              action: DTPrimaryButton(
                label: 'Add vehicle',
                icon: Icons.add_rounded,
                onPressed: () {
                  Navigator.of(context).pop();
                  AppNavigation.openAddVehicle(parentContext);
                },
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.55,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: controller.activeVehicles.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: DTSpacing.sm),
                itemBuilder: (context, index) {
                  final vehicle = controller.activeVehicles[index];
                  return DTVehicleCard(
                    vehicle: vehicle,
                    isSelected: vehicle.id == selectedId,
                    onTap: () async {
                      await controller.selectVehicle(vehicle.id);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: DTSpacing.lg),
          DTPrimaryButton(
            key: const Key('selectorAddVehicleButton'),
            label: 'Add another vehicle',
            icon: Icons.add_rounded,
            onPressed: () {
              Navigator.of(context).pop();
              AppNavigation.openAddVehicle(parentContext);
            },
          ),
        ],
      ),
    );
  }
}
