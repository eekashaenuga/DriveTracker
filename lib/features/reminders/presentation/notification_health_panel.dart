import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../core/notifications/local_notification_service.dart';

class NotificationHealthPanel extends StatelessWidget {
  const NotificationHealthPanel({this.showStatus = true, super.key});
  final bool showStatus;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriveTrackerController>();
    if (!c.localNotificationsSupported) return const SizedBox.shrink();
    final failed =
        c.notificationSyncError != null ||
        c.notificationFailureCount > 0 ||
        c.notificationTimezoneWarning != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showStatus)
            Text(
              c.notificationHealthLabel,
              key: const Key('notificationHealthLabel'),
            ),
          if (c.notificationTimezoneWarning != null)
            Text(c.notificationTimezoneWarning!),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (showStatus && !c.localReminderNotificationsPreferred)
                TextButton(
                  onPressed: c.isBusy
                      ? null
                      : () => c.setLocalReminderNotificationsEnabled(true),
                  child: const Text('Enable notifications'),
                ),
              if (c.localNotificationPermissionStatus ==
                      LocalNotificationPermissionStatus.denied ||
                  !showStatus)
                TextButton(
                  onPressed: () async {
                    final opened = await c.openAndroidNotificationSettings();
                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Open Android Settings → Apps → Vehnora → Notifications.',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Android notification settings'),
                ),
              if (failed)
                TextButton(
                  onPressed: () => c.refreshReminderEnvironment(force: true),
                  child: const Text('Retry synchronization'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
