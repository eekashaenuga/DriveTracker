import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../core/utilities/validation_exception.dart';
import '../domain/record_category.dart';
import 'category_name_dialog.dart';

class ManagedCategoriesScreen extends StatefulWidget {
  const ManagedCategoriesScreen({super.key});
  @override
  State<ManagedCategoriesScreen> createState() =>
      _ManagedCategoriesScreenState();
}

class _ManagedCategoriesScreenState extends State<ManagedCategoriesScreen> {
  RecordCategoryType _type = RecordCategoryType.expense;
  bool _archived = false;
  bool _busy = false;
  String? _error;
  late Future<List<RecordCategory>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = context.read<DriveTrackerController>().categoriesFor(
      _type,
      includeArchived: true,
    );
  }

  Future<void> _perform(Future<void> Function() action, String feedback) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(feedback)));
    } on ValidationException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not update categories. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _reload();
        });
      }
    }
  }

  Future<void> _name(
    List<RecordCategory> all, [
    RecordCategory? category,
  ]) async {
    final type = _type;
    final name = await showCategoryNameDialog(
      context,
      title: category == null
          ? 'New ${type.label.toLowerCase()} category'
          : 'Rename category',
      initialName: category?.name,
      existingNames: all.where((c) => c.id != category?.id).map((c) => c.name),
    );
    if (!mounted || name == null) return;
    final c = context.read<DriveTrackerController>();
    await _perform(() async {
      if (category == null) {
        await c.addCustomCategory(type: type, name: name);
      } else {
        await c.renameCategory(category.id, name);
      }
    }, category == null ? 'Category added.' : 'Category renamed.');
  }

  Future<void> _action(
    String action,
    RecordCategory category,
    List<RecordCategory> visible,
    List<RecordCategory> all,
    int index,
  ) async {
    final c = context.read<DriveTrackerController>();
    switch (action) {
      case 'Rename':
        await _name(all, category);
        break;
      case 'Archive':
        await _perform(
          () => c.archiveCategory(category.id, true),
          'Category archived. Existing records keep their category.',
        );
        break;
      case 'Restore':
        await _perform(
          () => c.archiveCategory(category.id, false),
          'Category restored.',
        );
        break;
      case 'Delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            scrollable: true,
            title: const Text('Delete category?'),
            content: Text(
              'Delete “${category.name}”? Categories used by records cannot be deleted. You can archive them instead.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) {
          await _perform(
            () => c.deleteCategory(category.id),
            'Category deleted.',
          );
        }
        break;
      case 'Move up':
        await _reorder(visible, index, index - 1);
        break;
      case 'Move down':
        await _reorder(visible, index, index + 1);
        break;
    }
  }

  Future<void> _reorder(List<RecordCategory> values, int from, int to) async {
    final ids = values.map((c) => c.id).toList();
    ids.insert(to, ids.removeAt(from));
    final c = context.read<DriveTrackerController>();
    await _perform(() => c.reorderCategories(_type, ids), 'Order updated.');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Manage categories'),
      actions: [
        IconButton(
          tooltip: 'Add category',
          onPressed: _busy
              ? null
              : () async {
                  try {
                    final all = await _future;
                    if (mounted) await _name(all);
                  } catch (_) {
                    if (mounted) {
                      setState(
                        () => _error = 'Could not load categories. Try again.',
                      );
                    }
                  }
                },
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final type in [
                  RecordCategoryType.expense,
                  RecordCategoryType.income,
                ])
                  ChoiceChip(
                    label: Text('${type.label} categories'),
                    selected: _type == type,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() {
                            _type = type;
                            _error = null;
                            _reload();
                          }),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Show archived'),
            value: _archived,
            onChanged: _busy ? null : (v) => setState(() => _archived = v),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: FutureBuilder<List<RecordCategory>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: () => setState(_reload),
                      child: const Text('Could not load categories. Retry'),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snapshot.data!;
                final values = all
                    .where((c) => c.isArchived == _archived)
                    .toList();
                if (values.isEmpty) {
                  return Center(
                    child: Text(
                      _archived
                          ? 'No archived categories.'
                          : 'No categories. Add one to get started.',
                    ),
                  );
                }
                return ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: values.length,
                  onReorderItem: (from, to) {
                    if (!_busy && !_archived) {
                      _reorder(values, from, to);
                    }
                  },
                  itemBuilder: (context, index) {
                    final category = values[index];
                    return ListTile(
                      key: ValueKey(category.id),
                      title: Text(category.name),
                      subtitle: Text(
                        category.isArchived
                            ? 'Archived • kept on existing records'
                            : category.systemCategory
                            ? 'Built-in • protected'
                            : 'Custom category',
                      ),
                      leading: category.systemCategory
                          ? const Icon(Icons.lock_outline)
                          : const Icon(Icons.label_outline),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!category.systemCategory ||
                              (!_archived && values.length > 1))
                            PopupMenuButton<String>(
                              tooltip: 'Actions for ${category.name}',
                              enabled: !_busy,
                              onSelected: (v) =>
                                  _action(v, category, values, all, index),
                              itemBuilder: (_) => [
                                if (!category.systemCategory) ...[
                                  const PopupMenuItem(
                                    value: 'Rename',
                                    child: Text('Rename'),
                                  ),
                                  PopupMenuItem(
                                    value: category.isArchived
                                        ? 'Restore'
                                        : 'Archive',
                                    child: Text(
                                      category.isArchived
                                          ? 'Restore'
                                          : 'Archive',
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'Delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                                if (!_archived && index > 0)
                                  const PopupMenuItem(
                                    value: 'Move up',
                                    child: Text('Move up'),
                                  ),
                                if (!_archived && index < values.length - 1)
                                  const PopupMenuItem(
                                    value: 'Move down',
                                    child: Text('Move down'),
                                  ),
                              ],
                            ),
                          if (!_archived && !_busy)
                            ReorderableDragStartListener(
                              index: index,
                              child: const SizedBox(
                                width: 48,
                                height: 48,
                                child: Tooltip(
                                  message: 'Drag to reorder',
                                  child: Icon(Icons.drag_handle),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
