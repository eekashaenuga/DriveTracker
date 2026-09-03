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
    final recentEntries = controller.recentOdometerEntries;

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
                    icon: Icons.history_rounded,
                    label: 'Readings',
                    value: recentEntries.length.toString(),
                    supportingText: 'Recent saved entries',
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
            const DTSectionHeader(title: 'Recent activity'),
            if (recentEntries.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: DTSpacing.lg),
                child: Text('No odometer readings have been saved yet.'),
              )
            else
              for (final entry in recentEntries)
                DTActivityRow(
                  icon: Icons.speed_rounded,
                  title: '${entry.sourceType.label} odometer reading',
                  subtitle: DTFormatters.dateTime(entry.eventDateTime),
                  trailing: Text(
                    DTFormatters.odometer(entry.odometer, unit),
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
            const DTSectionHeader(title: 'Coming later'),
            _FutureMetricsNotice(vehicleName: vehicle.name),
          ],
        ),
      ),
    );
  }
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

class _FutureMetricsNotice extends StatelessWidget {
  const _FutureMetricsNotice({required this.vehicleName});

  final String vehicleName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(DTSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.32,
        ),
        borderRadius: DTRadii.cardRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_graph_rounded, color: theme.colorScheme.secondary),
          const SizedBox(width: DTSpacing.md),
          Expanded(
            child: Text(
              'Fuel, service, expense and reminder metrics for $vehicleName will appear after those records are added in later milestones.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
