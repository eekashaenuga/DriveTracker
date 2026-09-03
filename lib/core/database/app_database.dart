import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import 'database_migrations.dart';

class AppDatabase {
  AppDatabase({sqflite.DatabaseFactory? databaseFactory, String? databasePath})
    : _databaseFactory = databaseFactory ?? sqflite.databaseFactory,
      _databasePath = databasePath == null ? null : p.normalize(databasePath);

  factory AppDatabase.production() => AppDatabase();

  factory AppDatabase.inMemory(sqflite.DatabaseFactory databaseFactory) {
    return AppDatabase(
      databaseFactory: databaseFactory,
      databasePath: sqflite.inMemoryDatabasePath,
    );
  }

  final sqflite.DatabaseFactory _databaseFactory;
  final String? _databasePath;
  sqflite.Database? _database;
  Future<sqflite.Database>? _opening;
  Future<void>? _closing;

  Future<sqflite.Database> get database async {
    final existing = _database;
    if (existing != null && existing.isOpen) {
      return existing;
    }

    final opening = _opening;
    if (opening != null) {
      return opening;
    }

    final future = _open();
    _opening = future;
    _database = await future;
    _opening = null;
    return _database!;
  }

  Future<T> transaction<T>(
    Future<T> Function(sqflite.Transaction txn) action,
  ) async {
    final db = await database;
    return db.transaction(action);
  }

  Future<void> close() {
    final closing = _closing;
    if (closing != null) {
      return closing;
    }

    final future = _close();
    _closing = future.whenComplete(() => _closing = null);
    return _closing!;
  }

  Future<void> _close() async {
    final opening = _opening;
    if (opening != null) {
      _database = await opening;
    }

    final db = _database;
    _database = null;
    _opening = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }

  Future<sqflite.Database> _open() async {
    final path =
        _databasePath ??
        p.join(await sqflite.getDatabasesPath(), 'drive_tracker.db');

    return _databaseFactory.openDatabase(
      path,
      options: sqflite.OpenDatabaseOptions(
        version: DatabaseMigrations.schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: DatabaseMigrations.createSchema,
        onUpgrade: DatabaseMigrations.migrate,
      ),
    );
  }
}
