import 'package:flutter/material.dart';

import '../../app/theme/dt_tokens.dart';
import '../../features/vehicles/domain/vehicle.dart';

class DTVehicleCard extends StatelessWidget {
  const DTVehicleCard({
    required this.vehicle,
    this.currentOdometerLabel,
    this.isSelected = false,
    this.onTap,
    this.trailing,
    super.key,
  });

  final Vehicle vehicle;
  final String? currentOdometerLabel;
  final bool isSelected;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
      borderRadius: DTRadii.cardRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: DTRadii.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(DTSpacing.lg),
          child: Row(
            children: [
              Icon(
                Icons.directions_car_rounded,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: DTSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            vehicle.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: DTSpacing.sm),
                          Icon(
                            Icons.check_circle_rounded,
                            color: theme.colorScheme.primary,
                            size: DTIconSizes.sm,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: DTSpacing.xs),
                    Text(
                      vehicle.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: DTSpacing.xs),
                    Text(
                      currentOdometerLabel ?? vehicle.registrationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: DTSpacing.sm),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
