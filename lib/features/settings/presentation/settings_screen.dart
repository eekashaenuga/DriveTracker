import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/notifications/local_notification_service.dart';
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
            const SizedBox(height: DTSpacing.xl),
            const DTSectionHeader(title: 'Notifications'),
            DTListCard(
              key: const Key('settingsLocalNotificationsTile'),
              icon: Icons.notifications_active_outlined,
              title: 'Local reminder notifications',
              subtitle: _notificationSubtitle(controller),
              accentColor: DTAccents.maintenance(context),
              trailing: Switch(
                key: const Key('settingsLocalNotificationsSwitch'),
                value: controller.localReminderNotificationsEnabled,
                onChanged: controller.localNotificationsSupported
                    ? (enabled) async {
                        await controller.setLocalReminderNotificationsEnabled(
                          enabled,
                        );
                        if (!context.mounted) {
                          return;
                        }
                        if (enabled &&
                            !controller.localReminderNotificationsEnabled) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Android notification permission was not granted. In-app reminders still work.',
                              ),
                            ),
                          );
                        }
                      }
                    : null,
              ),
              enabled: controller.localNotificationsSupported,
            ),
          ],
        ),
      ),
    );
  }
}

String _notificationSubtitle(DriveTrackerController controller) {
  if (!controller.localNotificationsSupported) {
    return 'Available on Android devices.';
  }
  if (controller.localReminderNotificationsEnabled) {
    return 'Date reminders are scheduled locally at 9:00 AM.';
  }
  if (controller.localNotificationPermissionStatus ==
      LocalNotificationPermissionStatus.denied) {
    return 'Off. Android permission is needed for local alerts.';
  }
  return 'Off. In-app reminders continue to work.';
}
