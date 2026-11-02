import '../../../shared/widgets/dt_bottom_sheet.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../core/calculations/analytics_date_range.dart';
import '../../../shared/widgets/analytics_date_range_picker.dart';
import '../../insights/presentation/insight_formatters.dart';
import '../domain/daily_activity.dart';
import '../domain/history_filter.dart';
import '../domain/history_page.dart';
import 'history_record_row.dart';
import 'history_filter_sheet.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({this.initialFilter, super.key});
  final HistoryFilter? initialFilter;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late HistoryFilter _filter = widget.initialFilter ?? const HistoryFilter();
  HistoryFilter? _inherited;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  List<DailyActivity> _rows = [];
  HistoryCursor? _next;
  bool _loading = true, _failed = false, _archived = false;
  bool _failedMore = false;
  int _generation = 0, _revision = -1;
  String _signature = '';
  @override
  void initState() {
    super.initState();
    _inherited = widget.initialFilter;
    _search.text = _filter.searchQuery;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  HistoryFilter _effective(DriveTrackerController c) {
    final base = _inherited;
    final ids =
        base?.vehicleIds ??
        (base?.vehicleId != null
            ? [base!.vehicleId!]
            : (_archived
                      ? [...c.activeVehicles, ...c.archivedVehicles]
                      : c.activeVehicles)
                  .map((v) => v.id)
                  .toList());
    var types = base?.recordTypes;
    if (base != null && base.type != DailyActivityType.all) {
      types = {base.type}.intersection(types ?? {base.type});
    }
    var category = _filter.categoryId ?? base?.categoryId;
    if (base?.categoryId != null &&
        _filter.categoryId != null &&
        base!.categoryId != _filter.categoryId) {
      types = {};
    }
    final requested = _filter.range.resolve(c.currentTime);
    final bounds = base?.range.resolve(c.currentTime);
    var start = requested.startInclusive, end = requested.endExclusive;
    if (bounds?.startInclusive != null &&
        (start == null || start.isBefore(bounds!.startInclusive!))) {
      start = bounds!.startInclusive;
    }
    if (bounds?.endExclusive != null &&
        (end == null || end.isAfter(bounds!.endExclusive!))) {
      end = bounds!.endExclusive;
    }
    AnalyticsDateRange range = _filter.range;
    if (start != null && end != null) {
      if (!start.isBefore(end)) {
        types = {};
        end = DateTime(start.year, start.month, start.day + 1);
      }
      range = AnalyticsDateRange.custom(
        start: start,
        endInclusive: DateTime(end.year, end.month, end.day - 1),
      );
    }
    return HistoryFilter(
      vehicleId: _filter.vehicleId,
      vehicleIds: ids,
      recordTypes: types,
      activityTypes: base?.activityTypes,
      selectedActivityType: _filter.selectedActivityType,
      operatingCostsOnly: base?.operatingCostsOnly ?? false,
      type: _filter.type,
      categoryId: category,
      range: range,
      searchQuery: _filter.searchQuery,
      sort: _filter.sort,
    );
  }

  void _reload({bool resetScroll = false}) {
    _signature = '';
    if (resetScroll && _scroll.hasClients) _scroll.jumpTo(0);
    setState(() {});
  }

  void _change(HistoryFilter filter) {
    _filter = filter;
    _rows = [];
    _next = null;
    _reload(resetScroll: true);
  }

  void _clear() {
    _debounce?.cancel();
    _search.clear();
    _inherited = null;
    _archived = false;
    _change(
      HistoryFilter(
        vehicleId: context.read<DriveTrackerController>().selectedVehicle?.id,
      ),
    );
  }

  Future<void> _load(HistoryFilter query, {bool more = false}) async {
    if (more && _loading) return;
    final generation = more ? _generation : ++_generation;
    final retainCount = more ? 0 : _rows.length;
    _loading = true;
    _failed = false;
    try {
      final controller = context.read<DriveTrackerController>();
      var page = await controller.historyPage(
        query,
        after: more ? _next : null,
      );
      final loaded = [...page.records];
      while (!more && loaded.length < retainCount && page.next != null) {
        if (!mounted || generation != _generation) return;
        page = await controller.historyPage(query, after: page.next);
        loaded.addAll(page.records);
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _rows = [if (more) ..._rows, ...loaded];
        _next = page.next;
        _loading = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _failed = true;
          _failedMore = more;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriveTrackerController>();
    if (_revision == -1) {
      _revision = c.historyRevision;
      if (widget.initialFilter == null) {
        _filter = _filter.copyWith(vehicleId: c.selectedVehicle?.id);
      }
    }
    final query = _effective(c);
    final signature = [
      query.vehicleId,
      query.vehicleIds,
      query.recordTypes,
      query.activityTypes,
      query.selectedActivityType,
      query.operatingCostsOnly,
      query.type,
      query.categoryId,
      query.range.preset,
      query.range.customStart,
      query.range.customEndInclusive,
      query.searchQuery,
      query.sort,
      c.historyRevision,
      c.currentTime.toLocal().toString().substring(0, 10),
    ].join('|');
    if (signature != _signature) {
      _signature = signature;
      _revision = c.historyRevision;
      unawaited(_load(query));
    }
    final vehicles = [
      ...c.activeVehicles,
      if (_archived) ...c.archivedVehicles,
    ];
    final filtered =
        _inherited != null ||
        _filter.type != DailyActivityType.all ||
        _filter.hasSearch ||
        _filter.categoryId != null ||
        _filter.selectedActivityType != null ||
        _filter.range != AnalyticsDateRange.all;
    final entries = <Object>[];
    String? month;
    for (final row in _rows) {
      final d = row.eventDateTime.toLocal();
      final key = '${d.year}-${d.month}';
      if (key != month) {
        month = key;
        entries.add(
          '${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][d.month - 1]} ${d.year}',
        );
      }
      entries.add(row);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: SafeArea(
        child: CustomScrollView(
          controller: _scroll,
          key: const Key('historyList'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        'historyVehicle_${_filter.vehicleId}_$_archived',
                      ),
                      isExpanded: true,
                      initialValue:
                          vehicles.any((v) => v.id == _filter.vehicleId)
                          ? _filter.vehicleId
                          : '__all__',
                      decoration: const InputDecoration(
                        labelText: 'Vehicle',
                        prefixIcon: Icon(Icons.directions_car_outlined),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: '__all__',
                          child: Text(
                            _archived
                                ? 'All vehicles including archived'
                                : 'All active vehicles',
                          ),
                        ),
                        for (final v in vehicles)
                          DropdownMenuItem(
                            value: v.id,
                            child: Text(
                              '${v.name}${v.isArchived ? ' (archived)' : ''}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => _change(
                        _filter.copyWith(vehicleId: v == '__all__' ? null : v),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('historySearchField'),
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: 'Search records',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _debounce?.cancel();
                                  _search.clear();
                                  _change(_filter.copyWith(searchQuery: ''));
                                },
                              ),
                      ),
                      onChanged: (v) {
                        setState(() {});
                        _debounce?.cancel();
                        _debounce = Timer(
                          const Duration(milliseconds: 300),
                          () => _change(_filter.copyWith(searchQuery: v)),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      key: const Key('historyFilterField'),
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final type in DailyActivityType.values)
                          FilterChip(
                            label: Text(
                              type == DailyActivityType.expense
                                  ? 'Expenses'
                                  : type.label,
                            ),
                            selected: _filter.type == type,
                            onSelected: (_) => _change(
                              _filter.copyWith(
                                type: type,
                                categoryId: null,
                                selectedActivityType: null,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          key: const Key('historyDateButton'),
                          onPressed: _dates,
                          icon: const Icon(Icons.date_range),
                          label: const Text('Date'),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final result = await showHistoryFilters(
                              context,
                              _filter,
                              _archived,
                            );
                            if (result != null && mounted) {
                              _archived = result.archived;
                              final selected = result.filter.vehicleId;
                              _change(
                                !result.archived &&
                                        selected != null &&
                                        !c.activeVehicles.any(
                                          (v) => v.id == selected,
                                        )
                                    ? result.filter.copyWith(vehicleId: null)
                                    : result.filter,
                              );
                            }
                          },
                          icon: const Icon(Icons.tune),
                          label: const Text('Filters'),
                        ),
                        PopupMenuButton<HistorySort>(
                          tooltip: 'Sort',
                          initialValue: _filter.sort,
                          onSelected: (v) => _change(_filter.copyWith(sort: v)),
                          itemBuilder: (_) => [
                            for (final v in HistorySort.values)
                              PopupMenuItem(
                                value: v,
                                child: Text(
                                  v == HistorySort.newest
                                      ? 'Newest first'
                                      : 'Oldest first',
                                ),
                              ),
                          ],
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: 48,
                              minWidth: 48,
                            ),
                            child: const Center(
                              widthFactor: 1,
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text('Sort'),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_inherited != null)
                      Text(
                        'From Insights: ${_rangeLabel(_inherited!.range)} · ${_inherited!.operatingCostsOnly ? 'operating costs' : _inherited!.type.label}. Filters narrow this scope.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (_inherited != null)
                          InputChip(
                            label: const Text('Insights scope'),
                            onDeleted: _clear,
                            deleteButtonTooltipMessage:
                                'Clear all filters and Insights scope',
                          ),
                        if (_filter.range != AnalyticsDateRange.all)
                          InputChip(
                            label: Text(_rangeLabel(_filter.range)),
                            onDeleted: () => _change(
                              _filter.copyWith(range: AnalyticsDateRange.all),
                            ),
                          ),
                        if (_filter.categoryId != null)
                          InputChip(
                            label: FutureBuilder(
                              future: c.categoryById(_filter.categoryId!),
                              builder: (context, snapshot) => Text(
                                snapshot.data?.name ?? 'Category selected',
                              ),
                            ),
                            onDeleted: () =>
                                _change(_filter.copyWith(categoryId: null)),
                          ),
                        if (_filter.selectedActivityType != null)
                          InputChip(
                            label: Text(_filter.selectedActivityType!.label),
                            onDeleted: () => _change(
                              _filter.copyWith(selectedActivityType: null),
                            ),
                          ),
                        if (_filter.sort == HistorySort.oldest)
                          InputChip(
                            label: const Text('Oldest first'),
                            onDeleted: () => _change(
                              _filter.copyWith(sort: HistorySort.newest),
                            ),
                          ),
                        if (_archived)
                          InputChip(
                            label: const Text('Archived vehicles included'),
                            onDeleted: () {
                              _archived = false;
                              _change(_filter.copyWith(vehicleId: null));
                            },
                          ),
                        if (filtered ||
                            _archived ||
                            _filter.sort != HistorySort.newest)
                          TextButton(
                            key: const Key('historyResetFiltersButton'),
                            onPressed: _clear,
                            child: const Text('Clear all'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (vehicles.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Text('No active vehicles'),
                      const Text(
                        'Add or restore a vehicle, or include archived vehicles in Filters.',
                      ),
                    ],
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                key: _loading ? null : const Key('historyLoaded'),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final item = entries[index];
                  if (item is String) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 20, bottom: 8),
                      child: Text(
                        item,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    );
                  }
                  final row = item as DailyActivity;
                  return HistoryRecordRow(
                    key: Key(
                      'historyActivity_${row.type.name}_${row.recordId}',
                    ),
                    record: row,
                    showVehicle: _filter.vehicleId == null,
                    onTap: () => _openActivity(row),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (_loading)
                      const CircularProgressIndicator()
                    else if (_failed) ...[
                      const Text('Could not load History.'),
                      TextButton(
                        onPressed: () => !_failedMore
                            ? _reload()
                            : setState(
                                () => unawaited(_load(query, more: true)),
                              ),
                        child: const Text('Retry'),
                      ),
                    ] else if (_rows.isEmpty && vehicles.isNotEmpty) ...[
                      Text(filtered ? 'No matching records' : 'No history yet'),
                      Text(
                        filtered ? 'No results match these filters.' : 'Fuel, expenses, income, service and odometer records will appear here.',
                      ),
                      if (filtered)
                        TextButton(
                          onPressed: _clear,
                          child: const Text('Clear filters'),
                        ),
                    ] else if (_next != null)
                      OutlinedButton(
                        onPressed: () {
                          setState(() => unawaited(_load(query, more: true)));
                        },
                        child: const Text('Load more records'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _rangeLabel(AnalyticsDateRange r) => switch (r.preset) {
    AnalyticsRangePreset.custom => InsightFormat.customRange(r),
    AnalyticsRangePreset.all => 'All time',
    AnalyticsRangePreset.week => 'This week',
    AnalyticsRangePreset.month => 'This month',
    AnalyticsRangePreset.year => 'This year',
    _ => r.preset.label,
  };
  Future<void> _dates() async {
    final preset = await showDTBottomSheet<AnalyticsRangePreset>(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in AnalyticsRangePreset.values)
                ListTile(
                  title: Text(_rangeLabel(AnalyticsDateRange.preset(p))),
                  onTap: () => Navigator.pop(context, p),
                ),
            ],
          ),
        ),
      ),
    );
    if (preset == null || !mounted) return;
    if (preset == AnalyticsRangePreset.custom) {
      final range = await pickAnalyticsDateRange(
        context: context,
        currentRange: _filter.range,
        currentDate: context.read<DriveTrackerController>().currentTime,
        pickerKey: const Key('historyCustomRangePicker'),
        helpText: 'Select history range',
      );
      if (range != null && mounted) _change(_filter.copyWith(range: range));
    } else {
      _change(_filter.copyWith(range: AnalyticsDateRange.preset(preset)));
    }
  }

  Future<void> _openActivity(DailyActivity activity) async {
    final controller = context.read<DriveTrackerController>();
    try {
      switch (activity.type) {
        case DailyActivityType.refuel:
          final refuel = await controller.refuelById(activity.recordId);
          if (refuel == null) throw StateError('Record no longer exists');
          if (mounted) {
            await AppNavigation.openRefuel(context, refuel: refuel);
          }
          break;
        case DailyActivityType.expense:
          final expense = await controller.expenseById(activity.recordId);
          if (expense == null) throw StateError('Record no longer exists');
          if (mounted) {
            await AppNavigation.openExpense(context, expense: expense);
          }
          break;
        case DailyActivityType.income:
          final income = await controller.incomeById(activity.recordId);
          if (income == null) throw StateError('Record no longer exists');
          if (mounted) {
            await AppNavigation.openIncome(context, income: income);
          }
          break;
        case DailyActivityType.service:
          final service = await controller.serviceRecordById(activity.recordId);
          if (service == null) throw StateError('Record no longer exists');
          if (mounted) {
            await AppNavigation.openService(context, service: service);
          }
          break;
        case DailyActivityType.odometer:
          if (mounted) {
            await AppNavigation.openRecordDetails(
              context,
              DailyActivityType.odometer,
              activity.recordId,
            );
          }
          break;
        case DailyActivityType.all:
          break;
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open this record. It may have been removed.',
            ),
          ),
        );
      }
    }
    if (mounted) _reload();
  }
}
