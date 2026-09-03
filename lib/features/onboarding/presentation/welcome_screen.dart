import 'package:flutter/material.dart';

import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../shared/widgets/dt_primary_button.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DTSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Icon(
                Icons.route_rounded,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: DTSpacing.xl),
              Text(
                'DriveTracker',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: DTSpacing.md),
              Text(
                'Everything about your vehicle,\nin one place.',
                style: theme.textTheme.headlineSmall?.copyWith(
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: DTSpacing.lg),
              Text(
                'Track mileage, fuel, maintenance and costs without an account or cloud dependency.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              DTPrimaryButton(
                key: const Key('addFirstVehicleButton'),
                label: 'Add your first vehicle',
                icon: Icons.add_rounded,
                onPressed: () =>
                    AppNavigation.openAddVehicle(context, firstVehicle: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
