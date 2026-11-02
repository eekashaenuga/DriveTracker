import '../../../shared/widgets/dt_bottom_sheet.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../domain/daily_activity.dart';
import '../domain/history_filter.dart';
import '../domain/income_activity.dart';
import '../domain/record_category.dart';

class HistoryFilterSelection {
  const HistoryFilterSelection(this.filter, this.archived);
  final HistoryFilter filter;
  final bool archived;
}

Future<HistoryFilterSelection?> showHistoryFilters(
  BuildContext context,
  HistoryFilter filter,
  bool archived,
) => showDTBottomSheet<HistoryFilterSelection>(
  context: context,
  builder: (_) => _Filters(filter: filter, archived: archived),
);

class _Filters extends StatefulWidget {
  const _Filters({required this.filter, required this.archived});
  final HistoryFilter filter;
  final bool archived;
  @override
  State<_Filters> createState() => _FiltersState();
}

class _FiltersState extends State<_Filters> {
  late HistoryFilter filter = widget.filter;
  late bool archived = widget.archived;
  late final Future<List<RecordCategory>> categories = _categories();
  Future<List<RecordCategory>> _categories() async {
    final c = context.read<DriveTrackerController>();
    return [
      ...await c.categoriesFor(
        RecordCategoryType.expense,
        includeArchived: true,
      ),
      ...await c.categoriesFor(
        RecordCategoryType.income,
        includeArchived: true,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      16,
      16,
      16 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'History filters',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if ([
            DailyActivityType.all,
            DailyActivityType.expense,
            DailyActivityType.income,
          ].contains(filter.type))
            FutureBuilder<List<RecordCategory>>(
              future: categories,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text(
                    'Could not load categories. Close and retry.',
                  );
                }
                if (!snapshot.hasData) return const LinearProgressIndicator();
                final values = snapshot.data!
                    .where(
                      (c) =>
                          filter.type == DailyActivityType.all ||
                          (filter.type == DailyActivityType.expense
                              ? c.type == RecordCategoryType.expense
                              : c.type == RecordCategoryType.income),
                    )
                    .toList();
                return DropdownButtonFormField<String>(
                  key: const Key('historyCategoryFilterField'),
                  isExpanded: true,
                  initialValue: values.any((c) => c.id == filter.categoryId)
                      ? filter.categoryId
                      : '__all__',
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem(
                      value: '__all__',
                      child: Text('All categories'),
                    ),
                    for (final c in values)
                      DropdownMenuItem(
                        value: c.id,
                        child: Text(
                          '${c.name}${c.isArchived ? ' (archived)' : ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(
                    () => filter = filter.copyWith(
                      categoryId: v == '__all__' ? null : v,
                    ),
                  ),
                );
              },
            ),
          if (filter.type == DailyActivityType.all ||
              filter.type == DailyActivityType.income)
            DropdownButtonFormField<IncomeActivityType?>(
              isExpanded: true,
              initialValue: filter.selectedActivityType,
              decoration: const InputDecoration(
                labelText: 'Saved activity type',
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All activity types'),
                ),
                for (final t in IncomeActivityType.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (v) => setState(
                () => filter = filter.copyWith(selectedActivityType: v),
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Include archived vehicles'),
            subtitle: const Text('Archived records remain read-only.'),
            value: archived,
            onChanged: (v) => setState(() => archived = v),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              HistoryFilterSelection(filter, archived),
            ),
            child: const Text('Apply filters'),
          ),
        ],
      ),
    ),
  );
}
