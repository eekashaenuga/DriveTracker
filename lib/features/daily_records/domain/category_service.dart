import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/utilities/id_generator.dart';
import '../../../core/utilities/validation_exception.dart';
import '../data/category_repository.dart';
import 'record_category.dart';

typedef Clock = DateTime Function();

class CategoryService {
  CategoryService({
    required this.categoryRepository,
    IdGenerator? idGenerator,
    Clock? clock,
  }) : _idGenerator = idGenerator ?? IdGenerator(),
       _clock = clock ?? (() => DateTime.now().toUtc());

  final CategoryRepository categoryRepository;
  final IdGenerator _idGenerator;
  final Clock _clock;

  Future<RecordCategory> createCustomCategory({
    required RecordCategoryType type,
    required String name,
    String? iconIdentifier,
  }) async {
    return categoryRepository.transaction((txn) async {
      final cleanName = name.trim();
      if (cleanName.isEmpty) {
        throw const ValidationException(['Category name is required.']);
      }
      final existingCategory = await categoryRepository.findByTypeAndName(
        type,
        cleanName,
        executor: txn,
      );
      if (existingCategory != null) {
        throw ValidationException([
          'A category named "$cleanName" already exists.',
        ]);
      }

      final now = _clock().toUtc();
      final category = RecordCategory(
        id: _idGenerator.newId('cat'),
        type: type,
        name: cleanName,
        iconIdentifier: iconIdentifier?.trim(),
        sortOrder: await categoryRepository.nextSortOrder(type, executor: txn),
        systemCategory: false,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
      );
      await categoryRepository.insert(category, executor: txn);
      return category;
    });
  }

  Future<void> rename(String id, String name) =>
      categoryRepository.transaction((txn) async {
        final category = await _custom(id, txn);
        final clean = name.trim();
        if (clean.isEmpty) {
          throw const ValidationException(['Category name is required.']);
        }
        final existing = await categoryRepository.findByTypeAndName(
          category.type,
          clean,
          executor: txn,
        );
        if (existing != null && existing.id != id) {
          throw const ValidationException([
            'That category name already exists, including archived categories.',
          ]);
        }
        await categoryRepository.update(
          _changed(category, {'name': clean}),
          executor: txn,
        );
      });

  Future<void> setArchived(String id, bool archived) =>
      categoryRepository.transaction((txn) async {
        final category = await _custom(id, txn);
        await categoryRepository.update(
          _changed(category, {'is_archived': archived ? 1 : 0}),
          executor: txn,
        );
      });

  Future<void> delete(String id) => categoryRepository.transaction((txn) async {
    await _custom(id, txn);
    if (await categoryRepository.isReferenced(id, executor: txn)) {
      throw const ValidationException([
        'This category is used by existing records. Archive it instead.',
      ]);
    }
    await categoryRepository.delete(id, executor: txn);
  });

  Future<void> reorder(RecordCategoryType type, List<String> ids) =>
      categoryRepository.transaction((txn) async {
        final categories = await categoryRepository.listByType(
          type,
          executor: txn,
        );
        if (ids.length != categories.length ||
            ids.toSet().length != ids.length ||
            !ids.toSet().containsAll(categories.map((c) => c.id))) {
          throw const ValidationException([
            'The list changed. Refresh and try again.',
          ]);
        }
        final byId = {for (final c in categories) c.id: c};
        for (var index = 0; index < ids.length; index++) {
          await categoryRepository.update(
            _changed(byId[ids[index]]!, {'sort_order': index * 10}),
            executor: txn,
          );
        }
      });

  Future<RecordCategory> _custom(
    String id,
    sqflite.DatabaseExecutor txn,
  ) async {
    final category = await categoryRepository.getById(id, executor: txn);
    if (category == null) {
      throw const ValidationException(['Category not found.']);
    }
    if (category.systemCategory) {
      throw const ValidationException([
        'Built-in categories cannot be renamed, archived or deleted.',
      ]);
    }
    return category;
  }

  RecordCategory _changed(
    RecordCategory category,
    Map<String, Object?> changes,
  ) => RecordCategory.fromMap({
    ...category.toMap(),
    ...changes,
    'updated_at': _clock().toUtc().toIso8601String(),
  });
}
