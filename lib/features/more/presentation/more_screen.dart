import 'package:flutter/material.dart';

import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../shared/widgets/dt_list_card.dart';
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
            const SizedBox(height: DTSpacing.xs),
            Text(
              'Vehicle records, tools and local data controls.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const DTSectionHeader(title: 'Vehicle'),
            _MoreTile(
              icon: Icons.directions_car_rounded,
              title: 'Vehicles',
              subtitle: 'Add, edit, switch and archive vehicles',
              accent: DTAccents.odometer,
              onTap: () => AppNavigation.openVehicles(context),
            ),
            const DTSectionHeader(title: 'Records'),
            _MoreTile(
              icon: Icons.history_rounded,
              title: 'History',
              subtitle: 'Fuel, expense, income, service and odometer records',
              accent: DTAccents.neutral,
              onTap: () => AppNavigation.openHistory(context),
            ),
            const SizedBox(height: DTSpacing.sm),
            _MoreTile(
              key: const Key('moreMaintenanceTile'),
              icon: Icons.handyman_rounded,
              title: 'Maintenance',
              subtitle: 'Service intervals and item history',
              accent: DTAccents.maintenance,
              onTap: () => AppNavigation.openMaintenance(context),
            ),
            const SizedBox(height: DTSpacing.sm),
            _MoreTile(
              key: const Key('moreDocumentsTile'),
              icon: Icons.description_outlined,
              title: 'Documents',
              subtitle: 'Insurance, MOT, receipts and files',
              accent: DTAccents.documents,
              onTap: () => AppNavigation.openDocuments(context),
            ),
            const SizedBox(height: DTSpacing.sm),
            _MoreTile(
              key: const Key('moreDataStorageTile'),
              icon: Icons.backup_outlined,
              title: 'Data & Storage',
              subtitle: 'Backup, restore, export and local usage',
              accent: DTAccents.storage,
              onTap: () => AppNavigation.openDataStorage(context),
            ),
            const DTSectionHeader(title: 'Tools'),
            _MoreTile(
              key: const Key('moreFuelCalculatorTile'),
              icon: Icons.calculate_outlined,
              title: 'Fuel Calculator',
              subtitle: 'Trip cost, sharing, fuel and price checks',
              accent: DTAccents.fuel,
              onTap: () => AppNavigation.openFuelCalculator(context),
            ),
            const DTSectionHeader(title: 'Preferences'),
            _MoreTile(
              icon: Icons.settings_rounded,
              title: 'Settings',
              subtitle: 'Theme preference and regional choices',
              accent: DTAccents.neutral,
              onTap: () => AppNavigation.openSettings(context),
            ),
            const DTSectionHeader(title: 'About'),
            _MoreTile(
              icon: Icons.lock_outline_rounded,
              title: 'Local-first by design',
              subtitle: 'Vehicle and daily record data stays on this device.',
              accent: DTAccents.storage,
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color Function(BuildContext context) accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return DTListCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      accentColor: accent(context),
      onTap: onTap,
      trailing: onTap == null ? null : const Icon(Icons.chevron_right_rounded),
    );
  }
}
