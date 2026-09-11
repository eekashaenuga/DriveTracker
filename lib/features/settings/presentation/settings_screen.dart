import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../shared/widgets/dt_list_card.dart';
import '../../../shared/widgets/dt_section_header.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(DTSpacing.lg),
          children: [
            const DTSectionHeader(title: 'Appearance'),
            Text('Theme', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: DTSpacing.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<ThemeMode>(
                selected: {controller.themeMode},
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_rounded),
                    label: Text('System'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_rounded),
                    label: Text('Light'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_rounded),
                    label: Text('Dark'),
                  ),
                ],
                onSelectionChanged: (selection) {
                  controller.setThemeMode(selection.first);
                },
              ),
            ),
            const SizedBox(height: DTSpacing.xl),
            const DTSectionHeader(title: 'Units & regional'),
            DTListCard(
              key: const Key('settingsDistanceUnitsTile'),
              icon: Icons.straighten_rounded,
              title: 'Distance units',
              subtitle: 'Units are set per vehicle.',
              accentColor: DTAccents.odometer(context),
              onTap: () => AppNavigation.openVehicleUnits(context),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
