import 'package:flutter/material.dart';

import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../shared/widgets/dt_section_header.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
              'More',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const DTSectionHeader(title: 'Manage'),
            ListTile(
              leading: const Icon(Icons.directions_car_rounded),
              title: const Text('Vehicles'),
              subtitle: const Text('Add, edit, switch and archive vehicles'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => AppNavigation.openVehicles(context),
            ),
            ListTile(
              leading: const Icon(Icons.settings_rounded),
              title: const Text('Settings'),
              subtitle: const Text('Theme preference'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => AppNavigation.openSettings(context),
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('History'),
              subtitle: const Text(
                'Fuel, expense, income and odometer records',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => AppNavigation.openHistory(context),
            ),
            const DTSectionHeader(title: 'Planned'),
            const _ComingLaterTile(
              icon: Icons.description_outlined,
              title: 'Documents',
            ),
            const _ComingLaterTile(
              icon: Icons.calculate_outlined,
              title: 'Fuel calculator',
            ),
            const _ComingLaterTile(
              icon: Icons.backup_outlined,
              title: 'Backup & restore',
            ),
            const _ComingLaterTile(
              icon: Icons.file_download_outlined,
              title: 'Export',
            ),
            const DTSectionHeader(title: 'About'),
            const ListTile(
              leading: Icon(Icons.lock_outline_rounded),
              title: Text('Local-first by design'),
              subtitle: Text(
                'Vehicle and daily record data stays on this device.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComingLaterTile extends StatelessWidget {
  const _ComingLaterTile({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: false,
      leading: Icon(icon),
      title: Text(title),
      subtitle: const Text('Planned for a later milestone'),
    );
  }
}
