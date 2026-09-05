import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/database/app_database.dart';
import '../domain/record_category.dart';

class CategoryRepository {
  CategoryRepository(this._database);

  final AppDatabase _database;

  Future<void> insert(
    RecordCategory category, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.insert('record_categories', category.toMap());
  }

  Future<void> update(
    RecordCategory category, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.update(
      'record_categories',
      category.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  Future<RecordCategory?> getById(
    String id, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'record_categories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return RecordCategory.fromMap(rows.first);
  }

  Future<List<RecordCategory>> listByType(
    RecordCategoryType type, {
    bool includeArchived = false,
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'record_categories',
      where: includeArchived ? 'type = ?' : 'type = ? AND is_archived = ?',
      whereArgs: includeArchived ? [type.storageValue] : [type.storageValue, 0],
      orderBy: 'sort_order ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(RecordCategory.fromMap).toList();
  }

  Future<RecordCategory?> findByTypeAndName(
    RecordCategoryType type,
    String name, {
    bool includeArchived = true,
    sqflite.DatabaseExecutor? executor,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      return null;
    }

    final db = await _executor(executor);
    final rows = await db.query(
      'record_categories',
      where: includeArchived
          ? 'type = ? AND name COLLATE NOCASE = ?'
          : 'type = ? AND name COLLATE NOCASE = ? AND is_archived = ?',
      whereArgs: includeArchived
          ? [type.storageValue, cleanName]
          : [type.storageValue, cleanName, 0],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return RecordCategory.fromMap(rows.first);
  }

  Future<int> nextSortOrder(
    RecordCategoryType type, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), 0) + 10 AS next_sort_order FROM record_categories WHERE type = ?',
      [type.storageValue],
    );
    return rows.first['next_sort_order'] as int;
  }

  Future<void> archive(
    String id,
    DateTime updatedAt, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.update(
      'record_categories',
      {'is_archived': 1, 'updated_at': updatedAt.toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<sqflite.DatabaseExecutor> _executor(
    sqflite.DatabaseExecutor? executor,
  ) async {
    return executor ?? await _database.database;
  }
}
