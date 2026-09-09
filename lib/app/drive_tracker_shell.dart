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
  final Set<int> _visitedTabs = {0};

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      _tab(0, const HomeScreen()),
      _tab(1, const InsightsScreen()),
      _tab(2, const RemindersScreen()),
      _tab(3, const MoreScreen()),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _ActionFab(
        onPressed: () => _showActionSheet(context),
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
              onTap: () => _selectTab(0),
            ),
            _NavItem(
              icon: Icons.insights_rounded,
              label: 'Insights',
              selected: _index == 1,
              onTap: () => _selectTab(1),
            ),
            const SizedBox(width: 68),
            _NavItem(
              icon: Icons.notifications_none_rounded,
              label: 'Reminders',
              selected: _index == 2,
              onTap: () => _selectTab(2),
            ),
            _NavItem(
              icon: Icons.more_horiz_rounded,
              label: 'More',
              selected: _index == 3,
              onTap: () => _selectTab(3),
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

  Widget _tab(int index, Widget child) {
    if (!_visitedTabs.contains(index)) {
      return const SizedBox.shrink();
    }
    return child;
  }

  void _selectTab(int index) {
    setState(() {
      _index = index;
      _visitedTabs.add(index);
    });
  }
}

class _ActionFab extends StatefulWidget {
  const _ActionFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_ActionFab> createState() => _ActionFabState();
}

class _ActionFabState extends State<_ActionFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        media?.disableAnimations == true || media?.accessibleNavigation == true;

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed && !reduceMotion ? 0.94 : 1,
        duration: reduceMotion ? Duration.zero : DTDurations.fast,
        curve: Curves.easeOutCubic,
        child: FloatingActionButton(
          key: const Key('mainActionButton'),
          onPressed: widget.onPressed,
          tooltip: 'Add entry',
          child: const Icon(Icons.add_rounded),
        ),
      ),
    );
  }

  void _setPressed(bool pressed) {
    if (_pressed == pressed || !mounted) {
      return;
    }
    setState(() => _pressed = pressed);
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
    final theme = Theme.of(context);
    final actions = [
      _ActionItem(
        key: const Key('actionRefuelTile'),
        icon: Icons.local_gas_station_rounded,
        title: 'Refuel',
        subtitle: 'Fuel cost, volume and odometer',
        onTap: () => AppNavigation.openRefuel(parentContext),
      ),
      _ActionItem(
        key: const Key('actionExpenseTile'),
        icon: Icons.payments_outlined,
        title: 'Expense',
        subtitle: 'Parking, tax, repairs and more',
        onTap: () => AppNavigation.openExpense(parentContext),
      ),
      _ActionItem(
        key: const Key('actionIncomeTile'),
        icon: Icons.work_outline_rounded,
        title: 'Income',
        subtitle: 'Vehicle-related income',
        onTap: () => AppNavigation.openIncome(parentContext),
      ),
      _ActionItem(
        key: const Key('actionServiceTile'),
        icon: Icons.build_circle_outlined,
        title: 'Service',
        subtitle: 'Garage visits and maintenance items',
        onTap: () => AppNavigation.openService(parentContext),
      ),
      _ActionItem(
        key: const Key('actionOdometerTile'),
        icon: Icons.speed_rounded,
        title: 'Odometer',
        subtitle: 'Record a manual reading',
        onTap: () => AppNavigation.openUpdateOdometer(parentContext),
      ),
    ];

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          DTSpacing.lg,
          0,
          DTSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + DTSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.add_circle_outline_rounded,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: DTSpacing.sm),
                Text(
                  'Add entry',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: DTSpacing.md),
            for (final action in actions) ...[
              if (action != actions.first) const SizedBox(height: DTSpacing.sm),
              _ActionTile(
                item: action,
                onTap: () {
                  Navigator.of(context).pop();
                  action.onTap();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionItem {
  const _ActionItem({
    required this.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key key;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.item, required this.onTap});

  final _ActionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      button: true,
      label: item.title,
      child: Material(
        key: item.key,
        color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: DTRadii.cardRadius,
        child: InkWell(
          borderRadius: DTRadii.cardRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DTSpacing.md,
              vertical: 10,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(DTRadii.card),
                  ),
                  child: Icon(
                    item.icon,
                    color: colors.onPrimaryContainer,
                    size: DTIconSizes.md,
                  ),
                ),
                const SizedBox(width: DTSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: DTSpacing.sm),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.onSurfaceVariant,
                  size: DTIconSizes.md,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
