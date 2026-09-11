import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/calculations/analytics_date_range.dart';
import '../../../core/utilities/formatters.dart';
import '../../../shared/widgets/analytics_date_range_picker.dart';
import '../../../shared/widgets/dt_activity_row.dart';
import '../../../shared/widgets/dt_empty_state.dart';
import '../../vehicles/domain/vehicle.dart';
import '../domain/daily_activity.dart';
import '../domain/history_filter.dart';
import '../domain/record_category.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({this.initialFilter, super.key});

  final HistoryFilter? initialFilter;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late HistoryFilter _filter = widget.initialFilter ?? const HistoryFilter();
  late final TextEditingController _searchController = TextEditingController(
    text: _filter.searchQuery,
  );
  Future<List<DailyActivity>>? _activitiesFuture;
  Future<List<RecordCategory>>? _categoriesFuture;
  String? _loadedSignature;
  bool _initializedScope = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    final selectedVehicle = controller.selectedVehicle;
    final vehicles = controller.activeVehicles;

    if (!_initializedScope && widget.initialFilter == null) {
      _initializedScope = true;
      _filter = _filter.copyWith(vehicleId: selectedVehicle?.id);
    } else if (!_initializedScope) {
      _initializedScope = true;
    }

    _categoriesFuture ??= _loadCategories(controller);
    _ensureActivities(controller);

    if (vehicles.isEmpty) {
      return const Scaffold(
        appBar: _HistoryAppBar(),
        body: DTEmptyState(
          icon: Icons.history_rounded,
          title: 'No active vehicles',
          body: 'Add a vehicle before reviewing History.',
        ),
      );
    }

    return Scaffold(
      appBar: const _HistoryAppBar(),
      body: SafeArea(
        child: ListView(
          key: const Key('historyList'),
          padding: const EdgeInsets.fromLTRB(
            DTSpacing.lg,
            DTSpacing.lg,
            DTSpacing.lg,
            DTSpacing.xxxl,
          ),
          children: [
            Text(
              'History',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: DTSpacing.xs),
            Text(
              _scopeLabel(vehicles),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: DTSpacing.lg),
            _HistoryFilters(
              filter: _filter,
              vehicles: vehicles,
              categoriesFuture: _categoriesFuture!,
              searchController: _searchController,
              onVehicleChanged: (vehicleId) {
                _setFilter(_filter.copyWith(vehicleId: vehicleId));
              },
              onTypeChanged: (type) {
                _setFilter(_filter.copyWith(type: type, categoryId: null));
              },
              onRangeChanged: (range) =>
                  _setFilter(_filter.copyWith(range: range)),
              onCustomRangeRequested: _showCustomRangeDialog,
              onCategoryChanged: (categoryId) {
                _setFilter(_filter.copyWith(categoryId: categoryId));
              },
              onSearchChanged: (value) {
                _setFilter(_filter.copyWith(searchQuery: value));
              },
              onReset: _resetFilters,
            ),
            const SizedBox(height: DTSpacing.lg),
            FutureBuilder<List<DailyActivity>>(
              future: _activitiesFuture,
              builder: (context, snapshot) {
                final activities = snapshot.data;
                if (activities == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (activities.isEmpty) {
                  return KeyedSubtree(
                    key: const Key('historyLoaded'),
                    child: Padding(
                      padding: const EdgeInsets.only(top: DTSpacing.xl),
                      child: _HistoryEmptyState(filtered: _hasResultFilters),
                    ),
                  );
                }
                return KeyedSubtree(
                  key: const Key('historyLoaded'),
                  child: _ActivityList(
                    activities: activities,
                    selectedVehicle: selectedVehicle,
                    showVehicle: _filter.vehicleId == null,
                    onTap: _openActivity,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<List<RecordCategory>> _loadCategories(
    DriveTrackerController controller,
  ) async {
    final expense = await controller.categoriesFor(RecordCategoryType.expense);
    final income = await controller.categoriesFor(RecordCategoryType.income);
    return [...expense, ...income];
  }

  void _ensureActivities(DriveTrackerController controller) {
    final signature = _filterSignature(_filter);
    if (_activitiesFuture == null || _loadedSignature != signature) {
      _loadedSignature = signature;
      _activitiesFuture = controller.history(_filter);
    }
  }

  void _setFilter(HistoryFilter filter) {
    setState(() {
      _filter = filter;
      _loadedSignature = null;
    });
  }

  void _resetFilters() {
    final selectedVehicle = context
        .read<DriveTrackerController>()
        .selectedVehicle;
    setState(() {
      _filter = HistoryFilter(vehicleId: selectedVehicle?.id);
      _searchController.clear();
      _loadedSignature = null;
    });
  }

  Future<void> _showCustomRangeDialog() async {
    final controller = context.read<DriveTrackerController>();
    final customRange = await pickAnalyticsDateRange(
      context: context,
      currentRange: _filter.range,
      currentDate: controller.currentTime,
      pickerKey: const Key('historyCustomRangePicker'),
      helpText: 'Select history range',
    );
    if (customRange == null || !mounted) {
      return;
    }
    _setFilter(_filter.copyWith(range: customRange));
  }

  Future<void> _openActivity(DailyActivity activity) async {
    final controller = context.read<DriveTrackerController>();
    switch (activity.type) {
      case DailyActivityType.refuel:
        final refuel = await controller.refuelById(activity.recordId);
        if (refuel != null && mounted) {
          await AppNavigation.openRefuel(context, refuel: refuel);
        }
        break;
      case DailyActivityType.expense:
        final expense = await controller.expenseById(activity.recordId);
        if (expense != null && mounted) {
          await AppNavigation.openExpense(context, expense: expense);
        }
        break;
      case DailyActivityType.income:
        final income = await controller.incomeById(activity.recordId);
        if (income != null && mounted) {
          await AppNavigation.openIncome(context, income: income);
        }
        break;
      case DailyActivityType.service:
        final service = await controller.serviceRecordById(activity.recordId);
        if (service != null && mounted) {
          await AppNavigation.openService(context, service: service);
        }
        break;
      case DailyActivityType.odometer:
        if (mounted) {
          final editRequested = await showDialog<bool>(
            context: context,
            builder: (_) => _OdometerActivityDialog(activity: activity),
          );
          if (editRequested == true && mounted) {
            final entry = await controller.odometerEntryById(activity.recordId);
            if (entry != null && mounted) {
              await AppNavigation.openEditOdometerEntry(context, entry);
            }
          }
        }
        break;
      case DailyActivityType.all:
        break;
    }
    if (mounted) {
      setState(() {
        _loadedSignature = null;
      });
    }
  }

  String _scopeLabel(List<Vehicle> vehicles) {
    final vehicleId = _filter.vehicleId;
    if (vehicleId == null) {
      return 'All vehicles';
    }
    for (final vehicle in vehicles) {
      if (vehicle.id == vehicleId) {
        return vehicle.description;
      }
    }
    return 'Selected vehicle';
  }

  String _filterSignature(HistoryFilter filter) {
    return [
      filter.vehicleId ?? 'all',
      filter.type.name,
      filter.range.preset.name,
      filter.range.customStart?.toIso8601String() ?? '',
      filter.range.customEndInclusive?.toIso8601String() ?? '',
      filter.categoryId ?? '',
      filter.searchQuery.trim(),
    ].join('|');
  }

  bool get _hasResultFilters {
    return _filter.type != DailyActivityType.all ||
        _filter.range != AnalyticsDateRange.all ||
        _filter.categoryId != null ||
        _filter.searchQuery.trim().isNotEmpty;
  }
}

class _HistoryAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _HistoryAppBar();

  @override
  Widget build(BuildContext context) {
    return AppBar(title: const Text('History'));
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _HistoryFilters extends StatelessWidget {
  const _HistoryFilters({
    required this.filter,
    required this.vehicles,
    required this.categoriesFuture,
    required this.searchController,
    required this.onVehicleChanged,
    required this.onTypeChanged,
    required this.onRangeChanged,
    required this.onCustomRangeRequested,
    required this.onCategoryChanged,
    required this.onSearchChanged,
    required this.onReset,
  });

  final HistoryFilter filter;
  final List<Vehicle> vehicles;
  final Future<List<RecordCategory>> categoriesFuture;
  final TextEditingController searchController;
  final ValueChanged<String?> onVehicleChanged;
  final ValueChanged<DailyActivityType> onTypeChanged;
  final ValueChanged<AnalyticsDateRange> onRangeChanged;
  final VoidCallback onCustomRangeRequested;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onReset;

  static const _allVehicles = '__all_vehicles__';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safeSelectedVehicleId =
        vehicles.any((vehicle) => vehicle.id == filter.vehicleId)
        ? filter.vehicleId
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: const Key('historyVehicleFilterField'),
          initialValue: safeSelectedVehicleId ?? _allVehicles,
          decoration: const InputDecoration(
            labelText: 'Vehicle',
            prefixIcon: Icon(Icons.directions_car_rounded),
          ),
          items: [
            const DropdownMenuItem(
              value: _allVehicles,
              child: Text('All vehicles'),
            ),
            for (final vehicle in vehicles)
              DropdownMenuItem(value: vehicle.id, child: Text(vehicle.name)),
          ],
          onChanged: (value) {
            onVehicleChanged(value == _allVehicles ? null : value);
          },
        ),
        const SizedBox(height: DTSpacing.md),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<DailyActivityType>(
            key: const Key('historyFilterField'),
            selected: {filter.type},
            segments: const [
              ButtonSegment(value: DailyActivityType.all, label: Text('All')),
              ButtonSegment(
                value: DailyActivityType.refuel,
                label: Text('Fuel'),
              ),
              ButtonSegment(
                value: DailyActivityType.service,
                label: Text('Service'),
              ),
              ButtonSegment(
                value: DailyActivityType.expense,
                label: Text('Expense'),
              ),
              ButtonSegment(
                value: DailyActivityType.income,
                label: Text('Income'),
              ),
              ButtonSegment(
                value: DailyActivityType.odometer,
                label: Text('Odometer'),
              ),
            ],
            onSelectionChanged: (selection) => onTypeChanged(selection.first),
          ),
        ),
        const SizedBox(height: DTSpacing.md),
        Wrap(
          spacing: DTSpacing.sm,
          runSpacing: DTSpacing.sm,
          children: [
            _RangeChip(
              key: const Key('historyRangeAll'),
              label: 'All time',
              selected: filter.range.preset == AnalyticsRangePreset.all,
              onSelected: () => onRangeChanged(AnalyticsDateRange.all),
            ),
            _RangeChip(
              key: const Key('historyRangeWeek'),
              label: 'This week',
              selected: filter.range.preset == AnalyticsRangePreset.week,
              onSelected: () => onRangeChanged(AnalyticsDateRange.week),
            ),
            _RangeChip(
              key: const Key('historyRangeMonth'),
              label: 'This month',
              selected: filter.range.preset == AnalyticsRangePreset.month,
              onSelected: () => onRangeChanged(AnalyticsDateRange.month),
            ),
            _RangeChip(
              key: const Key('historyRangeYear'),
              label: 'This year',
              selected: filter.range.preset == AnalyticsRangePreset.year,
              onSelected: () => onRangeChanged(AnalyticsDateRange.year),
            ),
            FilterChip(
              key: const Key('historyCustomRangeButton'),
              selected: filter.range.preset == AnalyticsRangePreset.custom,
              label: Text(customAnalyticsRangeLabel(filter.range)),
              onSelected: (_) => onCustomRangeRequested(),
            ),
          ],
        ),
        const SizedBox(height: DTSpacing.md),
        FutureBuilder<List<RecordCategory>>(
          future: categoriesFuture,
          builder: (context, snapshot) {
            final categories = _categoriesForType(
              snapshot.data ?? const [],
              filter.type,
            );
            if (categories.isEmpty) {
              return const SizedBox.shrink();
            }
            final selectedCategoryId =
                categories.any((category) => category.id == filter.categoryId)
                ? filter.categoryId
                : null;
            return DropdownButtonFormField<String>(
              key: const Key('historyCategoryFilterField'),
              initialValue: selectedCategoryId ?? '__all_categories__',
              decoration: const InputDecoration(
                labelText: 'Category',
                prefixIcon: Icon(Icons.category_rounded),
              ),
              items: [
                const DropdownMenuItem(
                  value: '__all_categories__',
                  child: Text('All categories'),
                ),
                for (final category in categories)
                  DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name),
                  ),
              ],
              onChanged: (value) {
                onCategoryChanged(value == '__all_categories__' ? null : value);
              },
            );
          },
        ),
        const SizedBox(height: DTSpacing.md),
        TextField(
          key: const Key('historySearchField'),
          controller: searchController,
          decoration: const InputDecoration(
            labelText: 'Search history',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          textInputAction: TextInputAction.search,
          onChanged: onSearchChanged,
        ),
        const SizedBox(height: DTSpacing.sm),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const Key('historyResetFiltersButton'),
            onPressed: onReset,
            icon: const Icon(Icons.refresh_rounded),
            label: Text('Reset filters', style: theme.textTheme.labelLarge),
          ),
        ),
      ],
    );
  }

  List<RecordCategory> _categoriesForType(
    List<RecordCategory> categories,
    DailyActivityType type,
  ) {
    switch (type) {
      case DailyActivityType.expense:
        return categories
            .where((category) => category.type == RecordCategoryType.expense)
            .toList();
      case DailyActivityType.income:
        return categories
            .where((category) => category.type == RecordCategoryType.income)
            .toList();
      case DailyActivityType.all:
        return categories;
      case DailyActivityType.refuel:
      case DailyActivityType.service:
      case DailyActivityType.odometer:
        return const [];
    }
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => onSelected(),
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return DTEmptyState(
      icon: filtered ? Icons.filter_alt_off_rounded : Icons.history_rounded,
      title: filtered ? 'No matching records' : 'No history yet',
      body: filtered ? 'No results match these filters.' : 'Fuel, expenses, income, service and odometer records will appear here.',
    );
  }
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({
    required this.activities,
    required this.selectedVehicle,
    required this.showVehicle,
    required this.onTap,
  });

  final List<DailyActivity> activities;
  final Vehicle? selectedVehicle;
  final bool showVehicle;
  final ValueChanged<DailyActivity> onTap;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    String? currentMonth;
    for (final activity in activities) {
      final month = _monthLabel(activity.eventDateTime);
      if (month != currentMonth) {
        currentMonth = month;
        children.add(
          Padding(
            padding: const EdgeInsets.only(
              top: DTSpacing.lg,
              bottom: DTSpacing.sm,
            ),
            child: Text(
              month,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        );
      }

      children.add(
        InkWell(
          key: Key(
            'historyActivity_${activity.type.name}_${activity.recordId}',
          ),
          onTap: activity.type == DailyActivityType.all
              ? null
              : () => onTap(activity),
          child: DTActivityRow(
            icon: _iconFor(activity.type),
            title: activity.title,
            subtitle: _subtitle(activity),
            trailing: _trailing(context, activity),
            accentColor: _activityColor(context, activity.type),
          ),
        ),
      );
    }
    return Column(children: children);
  }

  Widget? _trailing(BuildContext context, DailyActivity activity) {
    final amount = activity.amountMinor;
    if (amount == null) {
      return null;
    }
    final color = activity.type == DailyActivityType.income
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.onSurface;
    return Text(
      DTFormatters.moneyMinor(amount),
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: color, fontWeight: FontWeight.w800),
    );
  }

  String _subtitle(DailyActivity activity) {
    final unit = activity.vehicleDistanceUnit ?? selectedVehicle?.distanceUnit;
    final parts = <String>[
      DTFormatters.dateTime(activity.eventDateTime),
      if (showVehicle && activity.vehicleName != null) activity.vehicleName!,
      activity.subtitle,
      if (activity.odometer != null && unit != null)
        DTFormatters.odometer(activity.odometer, unit),
    ];
    return parts.where((part) => part.trim().isNotEmpty).join(' / ');
  }

  IconData _iconFor(DailyActivityType type) {
    return switch (type) {
      DailyActivityType.refuel => Icons.local_gas_station_rounded,
      DailyActivityType.expense => Icons.payments_outlined,
      DailyActivityType.income => Icons.work_outline_rounded,
      DailyActivityType.service => Icons.build_circle_outlined,
      DailyActivityType.odometer => Icons.speed_rounded,
      DailyActivityType.all => Icons.history_rounded,
    };
  }

  Color _activityColor(BuildContext context, DailyActivityType type) {
    return switch (type) {
      DailyActivityType.refuel => DTAccents.fuel(context),
      DailyActivityType.expense => DTAccents.expense(context),
      DailyActivityType.income => DTAccents.income(context),
      DailyActivityType.service => DTAccents.service(context),
      DailyActivityType.odometer => DTAccents.odometer(context),
      DailyActivityType.all => DTAccents.neutral(context),
    };
  }

  String _monthLabel(DateTime value) {
    final local = value.toLocal();
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[local.month - 1]} ${local.year}';
  }
}

class _OdometerActivityDialog extends StatelessWidget {
  const _OdometerActivityDialog({required this.activity});

  final DailyActivity activity;

  @override
  Widget build(BuildContext context) {
    final unit = activity.vehicleDistanceUnit ?? DistanceUnit.miles;
    return AlertDialog(
      key: const Key('historyOdometerDetails'),
      title: const Text('Odometer reading'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DTFormatters.odometer(activity.odometer, unit),
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: DTSpacing.sm),
          Text(DTFormatters.dateTime(activity.eventDateTime)),
          if (activity.vehicleName != null) ...[
            const SizedBox(height: DTSpacing.xs),
            Text(activity.vehicleName!),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('historyEditOdometerButton'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Edit'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
