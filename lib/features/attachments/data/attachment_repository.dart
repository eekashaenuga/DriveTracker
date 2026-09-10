import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/database/app_database.dart';
import '../domain/attachment.dart';

class AttachmentRepository {
  AttachmentRepository(this._database);

  final AppDatabase _database;

  Future<void> insert(
    Attachment attachment, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.insert('attachments', attachment.toMap());
  }

  Future<Attachment?> getById(
    String id, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'attachments',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Attachment.fromMap(rows.first);
  }

  Future<List<Attachment>> listForParent(
    AttachmentParentType parentType,
    String parentId, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'attachments',
      where: 'parent_type = ? AND parent_id = ?',
      whereArgs: [parentType.storageValue, parentId],
      orderBy: 'created_at ASC',
    );
    return rows.map(Attachment.fromMap).toList();
  }

  Future<void> delete(String id, {sqflite.DatabaseExecutor? executor}) async {
    final db = await _executor(executor);
    await db.delete('attachments', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteForParent(
    AttachmentParentType parentType,
    String parentId, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    await db.delete(
      'attachments',
      where: 'parent_type = ? AND parent_id = ?',
      whereArgs: [parentType.storageValue, parentId],
    );
  }

  Future<sqflite.DatabaseExecutor> _executor(
    sqflite.DatabaseExecutor? executor,
  ) async {
    return executor ?? await _database.database;
  }
}
