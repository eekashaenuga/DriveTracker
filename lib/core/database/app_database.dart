import 'dart:io';

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
  Future<void>? _snapshotting;

  sqflite.DatabaseFactory get databaseFactory => _databaseFactory;

  bool get isInMemory => _databasePath == sqflite.inMemoryDatabasePath;

  Future<String> get resolvedPath async => _resolvedPath();

  Future<sqflite.Database> get database async {
    final snapshotting = _snapshotting;
    if (snapshotting != null) {
      await _waitForSnapshotToFinish(snapshotting);
    }
    return _openForLifecycle();
  }

  Future<T> transaction<T>(
    Future<T> Function(sqflite.Transaction txn) action,
  ) async {
    final db = await database;
    return db.transaction(action);
  }

  Future<void> close() async {
    final snapshotting = _snapshotting;
    if (snapshotting != null) {
      await _waitForSnapshotToFinish(snapshotting);
    }
    await _closeForLifecycle();
  }

  Future<void> copyConsistentSnapshot(String targetPath) {
    return _copyConsistentSnapshot(targetPath, leaveClosedOnSuccess: false);
  }

  Future<void> copyConsistentSnapshotAndLeaveClosed(String targetPath) {
    return _copyConsistentSnapshot(targetPath, leaveClosedOnSuccess: true);
  }

  Future<void> _copyConsistentSnapshot(
    String targetPath, {
    required bool leaveClosedOnSuccess,
  }) {
    final snapshotting = _snapshotting;
    if (snapshotting != null) {
      return _waitForSnapshotToFinish(snapshotting).then(
        (_) => _copyConsistentSnapshot(
          targetPath,
          leaveClosedOnSuccess: leaveClosedOnSuccess,
        ),
      );
    }

    late final Future<void> snapshot;
    snapshot =
        _copyConsistentSnapshotLocked(
          targetPath,
          leaveClosedOnSuccess: leaveClosedOnSuccess,
        ).whenComplete(() {
          if (identical(_snapshotting, snapshot)) {
            _snapshotting = null;
          }
        });
    _snapshotting = snapshot;
    return snapshot;
  }

  Future<void> _waitForSnapshotToFinish(Future<void> snapshotting) async {
    try {
      await snapshotting;
    } catch (_) {
      // The snapshot caller receives the backup error. Unrelated database users
      // only need to wait for the recovery/reopen path to finish.
    }
  }

  Future<void> _copyConsistentSnapshotLocked(
    String targetPath, {
    required bool leaveClosedOnSuccess,
  }) async {
    if (isInMemory) {
      throw StateError('In-memory databases cannot be backed up to disk.');
    }

    final sourcePath = await resolvedPath;
    var shouldRecoverLiveDatabase = false;
    var copied = false;
    Object? snapshotError;
    StackTrace? snapshotStack;

    try {
      final db = await _openForLifecycle();
      await _checkpointWalIfNeeded(db);

      // SQLite writes outstanding rollback/WAL state into a consistent main DB
      // file during a clean close. After that point the source database file can
      // be copied without depending on sidecar -wal/-shm files.
      shouldRecoverLiveDatabase = true;
      await _closeForLifecycle();

      final target = File(targetPath);
      await target.parent.create(recursive: true);
      await File(sourcePath).copy(target.path);
      copied = true;
    } catch (error, stackTrace) {
      snapshotError = error;
      snapshotStack = stackTrace;
    }

    if (shouldRecoverLiveDatabase && (!copied || !leaveClosedOnSuccess)) {
      try {
        await _reopenAndVerify();
      } catch (reopenError) {
        final snapshotMessage = snapshotError == null
            ? 'Snapshot copied successfully'
            : 'Snapshot failed: $snapshotError';
        throw StateError(
          '$snapshotMessage, and the live database could not be reopened: '
          '$reopenError',
        );
      }
    }

    if (snapshotError != null) {
      Error.throwWithStackTrace(snapshotError, snapshotStack!);
    }
  }

  Future<sqflite.Database> _openForLifecycle() async {
    final closing = _closing;
    if (closing != null) {
      await closing;
    }

    final existing = _database;
    if (existing != null && existing.isOpen) {
      return existing;
    }

    final opening = _opening;
    if (opening != null) {
      final db = await opening;
      _database = db;
      return db;
    }

    final future = _open();
    _opening = future;
    try {
      final db = await future;
      _database = db;
      return db;
    } finally {
      if (identical(_opening, future)) {
        _opening = null;
      }
    }
  }

  Future<void> _closeForLifecycle() {
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

  Future<void> _checkpointWalIfNeeded(sqflite.Database db) async {
    final journalRows = await db.rawQuery('PRAGMA journal_mode');
    if (journalRows.isEmpty) {
      throw StateError('SQLite journal mode could not be inspected.');
    }
    final journalMode = journalRows.first.values.first
        ?.toString()
        .toLowerCase();
    if (journalMode == null || journalMode.isEmpty) {
      throw StateError('SQLite journal mode is unavailable.');
    }
    if (journalMode != 'wal') {
      return;
    }

    final checkpointRows = await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    if (checkpointRows.isEmpty) {
      throw StateError('SQLite WAL checkpoint returned no result.');
    }
    final values = checkpointRows.first.values.toList();
    final busy = _pragmaInt(
      checkpointRows.first['busy'] ?? (values.isEmpty ? null : values.first),
    );
    if (busy != 0) {
      throw StateError('SQLite WAL checkpoint could not complete.');
    }
  }

  Future<void> _reopenAndVerify() async {
    final db = await _openForLifecycle();
    final rows = await db.rawQuery('PRAGMA user_version');
    if (rows.isEmpty || rows.first.values.first is! int) {
      throw StateError('SQLite schema version could not be verified.');
    }
  }

  int _pragmaInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? -1;
  }

  Future<sqflite.Database> _open() async {
    final path = await _resolvedPath();

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

  Future<String> _resolvedPath() async {
    return _databasePath ??
        p.join(await sqflite.getDatabasesPath(), 'drive_tracker.db');
  }
}
