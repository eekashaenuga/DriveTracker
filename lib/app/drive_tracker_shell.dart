import 'package:flutter/material.dart';

import '../features/home/presentation/home_screen.dart';
import '../features/insights/presentation/insights_screen.dart';
import '../features/more/presentation/more_screen.dart';
import '../features/reminders/presentation/reminders_screen.dart';
import '../shared/widgets/dt_bottom_sheet.dart';
import 'router/app_navigation.dart';
import 'theme/dt_tokens.dart';

class DriveTrackerShell extends StatefulWidget {
  const DriveTrackerShell({super.key});

  @override
  State<DriveTrackerShell> createState() => _DriveTrackerShellState();
}

class _DriveTrackerShellState extends State<DriveTrackerShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      const HomeScreen(),
      const InsightsScreen(),
      const RemindersScreen(),
      const MoreScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        key: const Key('mainActionButton'),
        onPressed: () => _showActionSheet(context),
        tooltip: 'Add entry',
        child: const Icon(Icons.add_rounded),
      ),
      bottomNavigationBar: BottomAppBar(
        height: 78,
        padding: const EdgeInsets.symmetric(horizontal: DTSpacing.sm),
        child: Row(
          children: [
            _NavItem(
              icon: Icons.home_rounded,
              label: 'Home',
              selected: _index == 0,
              onTap: () => setState(() => _index = 0),
            ),
            _NavItem(
              icon: Icons.insights_rounded,
              label: 'Insights',
              selected: _index == 1,
              onTap: () => setState(() => _index = 1),
            ),
            const SizedBox(width: 68),
            _NavItem(
              icon: Icons.notifications_none_rounded,
              label: 'Reminders',
              selected: _index == 2,
              onTap: () => setState(() => _index = 2),
            ),
            _NavItem(
              icon: Icons.more_horiz_rounded,
              label: 'More',
              selected: _index == 3,
              onTap: () => setState(() => _index = 3),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showActionSheet(BuildContext context) {
    return showDTBottomSheet<void>(
      context: context,
      builder: (sheetContext) => _ActionSheet(parentContext: context),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(DTRadii.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: DTSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color),
                const SizedBox(height: DTSpacing.xs),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionSheet extends StatelessWidget {
  const _ActionSheet({required this.parentContext});

  final BuildContext parentContext;

  @override
  Widget build(BuildContext context) {
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
            'Add entry',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: DTSpacing.md),
          ListTile(
            leading: const Icon(Icons.speed_rounded),
            title: const Text('Odometer'),
            subtitle: const Text('Record a manual reading'),
            onTap: () {
              Navigator.of(context).pop();
              AppNavigation.openUpdateOdometer(parentContext);
            },
          ),
          const _ComingLaterTile(
            icon: Icons.local_gas_station_rounded,
            title: 'Refuel',
          ),
          const _ComingLaterTile(
            icon: Icons.build_circle_outlined,
            title: 'Service',
          ),
          const _ComingLaterTile(
            icon: Icons.payments_outlined,
            title: 'Expense',
          ),
          const _ComingLaterTile(
            icon: Icons.work_outline_rounded,
            title: 'Income',
          ),
        ],
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
