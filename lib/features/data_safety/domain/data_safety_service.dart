import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/database/app_database.dart';
import '../../../core/database/database_migrations.dart';
import '../../attachments/domain/attachment_io.dart';
import 'backup_manifest.dart';

class DataSafetyException implements Exception {
  const DataSafetyException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum DataSafetyFileSaveStatus { saved, cancelled }

class DataSafetyFileSaveResult {
  const DataSafetyFileSaveResult(this.status, {this.displayName});

  final DataSafetyFileSaveStatus status;
  final String? displayName;

  bool get saved => status == DataSafetyFileSaveStatus.saved;
}

class PickedBackupFile {
  const PickedBackupFile({
    required this.sourcePath,
    required this.fileName,
    this.mimeType,
    this.fileSize,
  });

  final String sourcePath;
  final String fileName;
  final String? mimeType;
  final int? fileSize;
}

abstract class DataSafetyFileBridge {
  Future<DataSafetyFileSaveResult> saveFile({
    required String sourcePath,
    required String suggestedName,
    required String mimeType,
  });

  Future<PickedBackupFile?> pickBackupFile();
}

class PlatformDataSafetyFileBridge implements DataSafetyFileBridge {
  const PlatformDataSafetyFileBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  final MethodChannel _channel;

  static const _channelName = 'drivetracker/data_safety';

  @override
  Future<PickedBackupFile?> pickBackupFile() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'pickBackupFile',
      );
      if (result == null) {
        return null;
      }
      final path = result['path'] as String?;
      final fileName = result['fileName'] as String?;
      if (path == null || fileName == null) {
        return null;
      }
      return PickedBackupFile(
        sourcePath: path,
        fileName: fileName,
        mimeType: result['mimeType'] as String?,
        fileSize: result['fileSize'] as int?,
      );
    } on MissingPluginException {
      throw const DataSafetyException('Backup file picking is unavailable.');
    } on PlatformException catch (error) {
      throw DataSafetyException(
        error.message ?? 'Could not open the selected backup.',
      );
    }
  }

  @override
  Future<DataSafetyFileSaveResult> saveFile({
    required String sourcePath,
    required String suggestedName,
    required String mimeType,
  }) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'saveFile',
        {
          'sourcePath': sourcePath,
          'suggestedName': suggestedName,
          'mimeType': mimeType,
        },
      );
      if (result == null) {
        return const DataSafetyFileSaveResult(
          DataSafetyFileSaveStatus.cancelled,
        );
      }
      return DataSafetyFileSaveResult(
        DataSafetyFileSaveStatus.saved,
        displayName: result['displayName'] as String? ?? suggestedName,
      );
    } on MissingPluginException {
      throw const DataSafetyException('File saving is unavailable.');
    } on PlatformException catch (error) {
      throw DataSafetyException(error.message ?? 'Could not save the file.');
    }
  }
}

class BackupCreationResult {
  const BackupCreationResult({
    required this.file,
    required this.manifest,
    required this.suggestedName,
  });

  final File file;
  final BackupManifest manifest;
  final String suggestedName;
}

class CsvExportCreationResult {
  const CsvExportCreationResult({
    required this.file,
    required this.suggestedName,
  });

  final File file;
  final String suggestedName;
}

class BackupInspection {
  const BackupInspection({
    required this.path,
    required this.fileName,
    required this.manifest,
    required this.attachmentPaths,
  });

  final String path;
  final String fileName;
  final BackupManifest manifest;
  final List<String> attachmentPaths;
}

class DataSafetyRestoreResult {
  const DataSafetyRestoreResult({
    required this.inspection,
    required this.safetyBackupPath,
  });

  final BackupInspection inspection;
  final String safetyBackupPath;
}

class DataStorageSummary {
  const DataStorageSummary({
    required this.databaseBytes,
    required this.attachmentCount,
    required this.attachmentBytes,
    required this.schemaVersion,
    required this.backupFormatVersion,
  });

  final int databaseBytes;
  final int attachmentCount;
  final int attachmentBytes;
  final int schemaVersion;
  final int backupFormatVersion;

  int get totalBytes => databaseBytes + attachmentBytes;
}

class DataSafetyService {
  DataSafetyService({
    required this.database,
    required this.attachmentStorage,
    DataSafetyFileBridge? fileBridge,
    DateTime Function()? clock,
    this.beforeSafetyBackup,
    this.afterDatabaseInstall,
  }) : _fileBridge = fileBridge ?? const PlatformDataSafetyFileBridge(),
       _clock = clock ?? (() => DateTime.now().toUtc());

  static const backupFormatVersion = 1;
  static const backupMimeType = 'application/vnd.drivetracker.backup';
  static const csvExportMimeType = 'application/zip';
  static const manifestPath = 'manifest.json';
  static const databaseArchivePath = 'database.sqlite';
  static const attachmentsRoot = 'attachments';

  static const _allTables = [
    'vehicles',
    'odometer_entries',
    'app_settings',
    'record_categories',
    'refuels',
    'expenses',
    'income_records',
    'maintenance_items',
    'services',
    'service_items',
    'documents',
    'attachments',
  ];

  final AppDatabase database;
  final AttachmentStorage attachmentStorage;
  final DataSafetyFileBridge _fileBridge;
  final DateTime Function() _clock;
  final Future<void> Function()? beforeSafetyBackup;
  final Future<void> Function()? afterDatabaseInstall;

  Future<BackupCreationResult> createBackup({
    Directory? outputDirectory,
  }) async {
    return _createBackup(
      outputDirectory: outputDirectory,
      leaveDatabaseClosedAfterSnapshot: false,
    );
  }

  Future<BackupCreationResult> _createBackup({
    Directory? outputDirectory,
    required bool leaveDatabaseClosedAfterSnapshot,
  }) async {
    final now = _clock().toUtc();
    final suggestedName = _timestampedName(
      'drivetracker-backup',
      'dtbackup',
      now,
    );
    final directory =
        outputDirectory ??
        await Directory.systemTemp.createTemp('drivetracker_backup_');
    await directory.create(recursive: true);
    final backupFile = File(p.join(directory.path, suggestedName));
    final manifest = await _writeBackupPackage(
      backupFile,
      now,
      leaveDatabaseClosedAfterSnapshot: leaveDatabaseClosedAfterSnapshot,
    );
    return BackupCreationResult(
      file: backupFile,
      manifest: manifest,
      suggestedName: suggestedName,
    );
  }

  Future<DataSafetyFileSaveResult> createAndSaveBackup() async {
    final backup = await createBackup();
    try {
      return await _fileBridge.saveFile(
        sourcePath: backup.file.path,
        suggestedName: backup.suggestedName,
        mimeType: backupMimeType,
      );
    } finally {
      await _deleteFileBestEffort(backup.file);
    }
  }

  Future<CsvExportCreationResult> createCsvExport({
    Directory? outputDirectory,
  }) async {
    final now = _clock().toUtc();
    final suggestedName = _timestampedName(
      'drivetracker-csv-export',
      'zip',
      now,
    );
    final directory =
        outputDirectory ??
        await Directory.systemTemp.createTemp('drivetracker_export_');
    await directory.create(recursive: true);
    final exportFile = File(p.join(directory.path, suggestedName));
    await _writeCsvExportPackage(exportFile, now);
    return CsvExportCreationResult(
      file: exportFile,
      suggestedName: suggestedName,
    );
  }

  Future<DataSafetyFileSaveResult> createAndSaveCsvExport() async {
    final export = await createCsvExport();
    try {
      return await _fileBridge.saveFile(
        sourcePath: export.file.path,
        suggestedName: export.suggestedName,
        mimeType: csvExportMimeType,
      );
    } finally {
      await _deleteFileBestEffort(export.file);
    }
  }

  Future<BackupInspection?> pickAndInspectBackup() async {
    final picked = await _fileBridge.pickBackupFile();
    if (picked == null) {
      return null;
    }
    return inspectBackupFile(picked.sourcePath, fileName: picked.fileName);
  }

  Future<BackupInspection> inspectBackupFile(
    String path, {
    String? fileName,
  }) async {
    final decoded = await _decodeBackupFile(File(path));
    return _inspectDecodedBackup(
      decoded.archive,
      path: path,
      fileName: fileName ?? p.basename(path),
    );
  }

  Future<DataSafetyRestoreResult> restoreBackupFromFile(
    String path, {
    String? fileName,
  }) async {
    final decoded = await _decodeBackupFile(File(path));
    final inspection = await _inspectDecodedBackup(
      decoded.archive,
      path: path,
      fileName: fileName ?? p.basename(path),
    );
    final stageDirectory = await Directory.systemTemp.createTemp(
      'drivetracker_restore_',
    );
    final stagedDatabase = File(
      p.join(stageDirectory.path, databaseArchivePath),
    );
    final stagedAttachmentRoot = Directory(
      p.join(stageDirectory.path, 'files'),
    );

    try {
      await _materializeRestoreStage(
        decoded.archive,
        stagedDatabase: stagedDatabase,
        stagedAttachmentRoot: stagedAttachmentRoot,
        attachmentPaths: inspection.attachmentPaths,
      );
      await beforeSafetyBackup?.call();
      final safetyDirectory = await _safetyBackupDirectory();
      final safetyBackup = await _createBackup(
        outputDirectory: safetyDirectory,
        leaveDatabaseClosedAfterSnapshot: true,
      );
      await _installStagedRestore(
        stagedDatabase: stagedDatabase,
        stagedAttachmentRoot: stagedAttachmentRoot,
      );
      return DataSafetyRestoreResult(
        inspection: inspection,
        safetyBackupPath: safetyBackup.file.path,
      );
    } finally {
      if (await stageDirectory.exists()) {
        await stageDirectory.delete(recursive: true);
      }
    }
  }

  Future<DataStorageSummary> storageSummary() async {
    final dbPath = await database.resolvedPath;
    final databaseBytes = await _databaseFilesSize(dbPath);
    final db = await database.database;
    final schemaVersion = await _schemaVersion(db);
    final rows = await _attachmentRows(db, schemaVersion: schemaVersion);
    var attachmentBytes = 0;
    for (final row in rows) {
      final storedPath = _safeAttachmentPath(row['stored_path'] as String);
      try {
        final file = File(
          await attachmentStorage.resolveAbsolutePath(storedPath),
        );
        if (await file.exists()) {
          attachmentBytes += await file.length();
        }
      } catch (_) {
        // Storage summary should still load if a file has gone missing.
      }
    }
    return DataStorageSummary(
      databaseBytes: databaseBytes,
      attachmentCount: rows.length,
      attachmentBytes: attachmentBytes,
      schemaVersion: schemaVersion,
      backupFormatVersion: backupFormatVersion,
    );
  }

  Future<BackupManifest> _writeBackupPackage(
    File backupFile,
    DateTime now, {
    required bool leaveDatabaseClosedAfterSnapshot,
  }) async {
    if (database.isInMemory) {
      throw const DataSafetyException('Backups need a file-backed database.');
    }
    final workDirectory = await Directory.systemTemp.createTemp(
      'drivetracker_snapshot_',
    );
    final snapshotDatabase = File(
      p.join(workDirectory.path, databaseArchivePath),
    );
    sqflite.Database? snapshotDb;
    var snapshotCopied = false;
    try {
      if (leaveDatabaseClosedAfterSnapshot) {
        await database.copyConsistentSnapshotAndLeaveClosed(
          snapshotDatabase.path,
        );
      } else {
        await database.copyConsistentSnapshot(snapshotDatabase.path);
      }
      snapshotCopied = true;
      snapshotDb = await _openDetachedDatabase(snapshotDatabase.path);
      final schemaVersion = await _validateOpenDatabase(snapshotDb);
      final counts = await _tableCounts(
        snapshotDb,
        schemaVersion: schemaVersion,
      );
      final rows = await _attachmentRows(
        snapshotDb,
        schemaVersion: schemaVersion,
      );
      final attachments = <BackupAttachmentEntry>[];
      for (final row in rows) {
        attachments.add(await _attachmentEntryFor(row));
      }
      final manifest = BackupManifest(
        backupFormatVersion: backupFormatVersion,
        schemaVersion: schemaVersion,
        createdAtUtc: now,
        databasePath: databaseArchivePath,
        databaseBytes: await snapshotDatabase.length(),
        tableCounts: counts,
        attachments: attachments,
      );
      final archive = Archive()
        ..add(ArchiveFile.string(manifestPath, _prettyJson(manifest.toJson())))
        ..add(
          ArchiveFile.bytes(
            databaseArchivePath,
            await snapshotDatabase.readAsBytes(),
          ),
        );
      for (final attachment in attachments) {
        final file = File(
          await attachmentStorage.resolveAbsolutePath(attachment.storedPath),
        );
        archive.add(
          ArchiveFile.bytes(attachment.archivePath, await file.readAsBytes()),
        );
      }
      await backupFile.writeAsBytes(
        ZipEncoder().encodeBytes(archive, modified: now),
        flush: true,
      );
      return manifest;
    } catch (error, stackTrace) {
      if (leaveDatabaseClosedAfterSnapshot && snapshotCopied) {
        try {
          await database.database;
        } catch (_) {
          throw const DataSafetyException(
            'Backup failed after taking a database snapshot, and the current '
            'database could not be reopened.',
          );
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      await snapshotDb?.close();
      if (await workDirectory.exists()) {
        await workDirectory.delete(recursive: true);
      }
    }
  }

  Future<void> _writeCsvExportPackage(File exportFile, DateTime now) async {
    if (database.isInMemory) {
      throw const DataSafetyException(
        'CSV export needs a file-backed database.',
      );
    }
    final workDirectory = await Directory.systemTemp.createTemp(
      'drivetracker_csv_snapshot_',
    );
    final snapshotDatabase = File(
      p.join(workDirectory.path, databaseArchivePath),
    );
    sqflite.Database? snapshotDb;
    try {
      await database.copyConsistentSnapshot(snapshotDatabase.path);
      snapshotDb = await _openDetachedDatabase(snapshotDatabase.path);
      final schemaVersion = await _validateOpenDatabase(snapshotDb);
      final archive = Archive()
        ..add(
          ArchiveFile.string(
            'README.txt',
            'DriveTracker CSV export\n'
                'Created: ${now.toIso8601String()}\n'
                'Schema version: $schemaVersion\n',
          ),
        );
      for (final table in _requiredTablesFor(schemaVersion)) {
        final columns = await _columnsFor(snapshotDb, table);
        final rows = await snapshotDb.query(table, orderBy: _orderByFor(table));
        archive.add(
          ArchiveFile.string(
            'csv/$table.csv',
            _csvFor(rows: rows, columns: columns),
          ),
        );
      }
      await exportFile.writeAsBytes(
        ZipEncoder().encodeBytes(archive, modified: now),
        flush: true,
      );
    } finally {
      await snapshotDb?.close();
      if (await workDirectory.exists()) {
        await workDirectory.delete(recursive: true);
      }
    }
  }

  Future<BackupInspection> _inspectDecodedBackup(
    Archive archive, {
    required String path,
    required String fileName,
  }) async {
    final manifestEntry = _requiredArchiveFile(archive, manifestPath);
    final databaseEntry = _requiredArchiveFile(archive, databaseArchivePath);
    if (databaseEntry.size <= 0) {
      throw const DataSafetyException('Backup database is empty.');
    }
    final manifest = _parseManifest(manifestEntry);
    if (manifest.backupFormatVersion != backupFormatVersion) {
      throw DataSafetyException(
        'Backup format ${manifest.backupFormatVersion} is not supported.',
      );
    }
    if (manifest.databasePath != databaseArchivePath) {
      throw const DataSafetyException(
        'Backup manifest database path is invalid.',
      );
    }
    if (manifest.databaseBytes != databaseEntry.size) {
      throw const DataSafetyException(
        'Backup database size does not match manifest.',
      );
    }
    final tempDirectory = await Directory.systemTemp.createTemp(
      'drivetracker_validate_',
    );
    final tempDatabase = File(p.join(tempDirectory.path, databaseArchivePath));
    sqflite.Database? db;
    try {
      await tempDatabase.writeAsBytes(_entryBytes(databaseEntry), flush: true);
      db = await _openDetachedDatabase(tempDatabase.path);
      final schemaVersion = await _validateOpenDatabase(db);
      if (schemaVersion != manifest.schemaVersion) {
        throw const DataSafetyException(
          'Backup database schema does not match manifest.',
        );
      }
      final counts = await _tableCounts(db, schemaVersion: schemaVersion);
      if (!_sameCounts(counts, manifest.tableCounts)) {
        throw const DataSafetyException(
          'Backup table counts do not match manifest.',
        );
      }
      final rows = await _attachmentRows(db, schemaVersion: schemaVersion);
      final attachmentPaths = rows
          .map((row) => _safeAttachmentPath(row['stored_path'] as String))
          .toList();
      _validateAttachmentEntries(
        archive: archive,
        rows: rows,
        manifest: manifest,
        attachmentPaths: attachmentPaths,
      );
      return BackupInspection(
        path: path,
        fileName: fileName,
        manifest: manifest,
        attachmentPaths: attachmentPaths,
      );
    } on DataSafetyException {
      rethrow;
    } catch (_) {
      throw const DataSafetyException(
        'Backup database could not be validated.',
      );
    } finally {
      await db?.close();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    }
  }

  Future<void> _materializeRestoreStage(
    Archive archive, {
    required File stagedDatabase,
    required Directory stagedAttachmentRoot,
    required List<String> attachmentPaths,
  }) async {
    final databaseEntry = _requiredArchiveFile(archive, databaseArchivePath);
    await stagedDatabase.parent.create(recursive: true);
    await stagedDatabase.writeAsBytes(_entryBytes(databaseEntry), flush: true);
    for (final attachmentPath in attachmentPaths) {
      final entry = _requiredArchiveFile(archive, attachmentPath);
      final target = File(p.join(stagedAttachmentRoot.path, attachmentPath));
      final rootPath = p.normalize(stagedAttachmentRoot.path);
      final targetPath = p.normalize(target.path);
      if (targetPath != rootPath && !p.isWithin(rootPath, targetPath)) {
        throw const DataSafetyException('Backup attachment path is invalid.');
      }
      await target.parent.create(recursive: true);
      await target.writeAsBytes(_entryBytes(entry), flush: true);
    }
  }

  Future<void> _installStagedRestore({
    required File stagedDatabase,
    required Directory stagedAttachmentRoot,
  }) async {
    final dbPath = await database.resolvedPath;
    final attachmentRoot = await attachmentStorage.managedRootDirectory();
    final rollbackDirectory = await Directory.systemTemp.createTemp(
      'drivetracker_rollback_',
    );
    final rollbackAttachments = Directory(
      p.join(rollbackDirectory.path, 'files'),
    );

    await database.close();
    try {
      await _copyCurrentDatabaseToRollback(dbPath, rollbackDirectory);
      if (await attachmentRoot.exists()) {
        await _copyDirectory(attachmentRoot, rollbackAttachments);
      }

      await _deleteDatabaseFiles(dbPath);
      await File(dbPath).parent.create(recursive: true);
      await stagedDatabase.copy(dbPath);

      if (await attachmentRoot.exists()) {
        await attachmentRoot.delete(recursive: true);
      }
      await _copyDirectory(stagedAttachmentRoot, attachmentRoot);

      await afterDatabaseInstall?.call();
      final db = await database.database;
      await _validateOpenDatabase(db);
    } catch (_) {
      await database.close();
      await _deleteDatabaseFiles(dbPath);
      await _restoreDatabaseFromRollback(dbPath, rollbackDirectory);
      if (await attachmentRoot.exists()) {
        await attachmentRoot.delete(recursive: true);
      }
      if (await rollbackAttachments.exists()) {
        await _copyDirectory(rollbackAttachments, attachmentRoot);
      } else {
        await attachmentRoot.create(recursive: true);
      }
      await database.database;
      throw const DataSafetyException(
        'Restore failed. Your existing data was kept.',
      );
    } finally {
      if (await rollbackDirectory.exists()) {
        await rollbackDirectory.delete(recursive: true);
      }
    }
  }

  Future<BackupAttachmentEntry> _attachmentEntryFor(
    Map<String, Object?> row,
  ) async {
    final storedPath = _safeAttachmentPath(row['stored_path'] as String);
    final file = File(await attachmentStorage.resolveAbsolutePath(storedPath));
    if (!await file.exists()) {
      throw DataSafetyException(
        'Attachment "${row['file_name']}" is missing and cannot be backed up.',
      );
    }
    final actualSize = await file.length();
    if (actualSize <= 0) {
      throw DataSafetyException(
        'Attachment "${row['file_name']}" is empty and cannot be backed up.',
      );
    }
    final recordedSize = row['file_size'] as int?;
    if (recordedSize != null && recordedSize != actualSize) {
      throw DataSafetyException(
        'Attachment "${row['file_name']}" no longer matches its metadata.',
      );
    }
    return BackupAttachmentEntry(
      id: row['id'] as String,
      storedPath: storedPath,
      archivePath: storedPath,
      fileName: row['file_name'] as String,
      fileSize: actualSize,
      parentType: row['parent_type'] as String,
      parentId: row['parent_id'] as String,
      mimeType: row['mime_type'] as String?,
    );
  }

  void _validateAttachmentEntries({
    required Archive archive,
    required List<Map<String, Object?>> rows,
    required BackupManifest manifest,
    required List<String> attachmentPaths,
  }) {
    if (manifest.attachments.length != rows.length) {
      throw const DataSafetyException(
        'Backup attachment count does not match the database.',
      );
    }
    final manifestByPath = {
      for (final attachment in manifest.attachments)
        _safeAttachmentPath(attachment.storedPath): attachment,
    };
    if (manifestByPath.length != manifest.attachments.length) {
      throw const DataSafetyException(
        'Backup manifest has duplicate attachments.',
      );
    }
    final databasePaths = attachmentPaths.toSet();
    final archiveAttachmentPaths = archive
        .where((entry) => entry.isFile)
        .map((entry) => _normalizeArchivePath(entry.name))
        .where((name) => name.startsWith('$attachmentsRoot/'))
        .toSet();
    if (!_sameStringSet(databasePaths, archiveAttachmentPaths)) {
      throw const DataSafetyException(
        'Backup attachment files do not match the database.',
      );
    }

    for (final row in rows) {
      final storedPath = _safeAttachmentPath(row['stored_path'] as String);
      final entry = _requiredArchiveFile(archive, storedPath);
      final manifestEntry = manifestByPath[storedPath];
      if (manifestEntry == null) {
        throw const DataSafetyException(
          'Backup manifest is missing an attachment entry.',
        );
      }
      if (manifestEntry.archivePath != storedPath ||
          manifestEntry.id != row['id'] ||
          manifestEntry.parentType != row['parent_type'] ||
          manifestEntry.parentId != row['parent_id'] ||
          manifestEntry.fileName != row['file_name']) {
        throw const DataSafetyException(
          'Backup attachment metadata does not match the database.',
        );
      }
      final recordedSize = row['file_size'] as int?;
      if (manifestEntry.fileSize != entry.size ||
          (recordedSize != null && recordedSize != entry.size) ||
          entry.size <= 0) {
        throw const DataSafetyException(
          'Backup attachment size does not match metadata.',
        );
      }
    }
  }

  BackupManifest _parseManifest(ArchiveFile manifestEntry) {
    try {
      final text = utf8.decode(_entryBytes(manifestEntry));
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Manifest is not an object.');
      }
      return BackupManifest.fromJson(decoded);
    } catch (_) {
      throw const DataSafetyException('Backup manifest is missing or invalid.');
    }
  }

  Future<_DecodedBackup> _decodeBackupFile(File file) async {
    if (!await file.exists()) {
      throw const DataSafetyException('Backup file could not be found.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const DataSafetyException('Backup file is empty.');
    }
    final seen = <String>{};
    final duplicateNames = <String>[];
    try {
      final archive = ZipDecoder().decodeBytes(
        bytes,
        callback: (entry) {
          final name = _normalizeArchivePath(entry.name);
          if (!seen.add(name)) {
            duplicateNames.add(name);
          }
        },
      );
      if (duplicateNames.isNotEmpty) {
        throw DataSafetyException(
          'Backup contains duplicate entry "${duplicateNames.first}".',
        );
      }
      for (final entry in archive) {
        final name = _normalizeArchivePath(entry.name);
        final allowed =
            name == manifestPath ||
            name == databaseArchivePath ||
            name.startsWith('$attachmentsRoot/');
        if (!allowed) {
          throw DataSafetyException(
            'Backup contains unexpected entry "$name".',
          );
        }
      }
      return _DecodedBackup(archive);
    } on DataSafetyException {
      rethrow;
    } catch (_) {
      throw const DataSafetyException(
        'Backup file is not a valid DriveTracker backup.',
      );
    }
  }

  ArchiveFile _requiredArchiveFile(Archive archive, String name) {
    final entry = archive.find(name);
    if (entry == null || !entry.isFile) {
      throw DataSafetyException('Backup is missing "$name".');
    }
    return entry;
  }

  List<int> _entryBytes(ArchiveFile entry) {
    final bytes = entry.readBytes();
    if (bytes == null) {
      throw DataSafetyException(
        'Backup entry "${entry.name}" could not be read.',
      );
    }
    return bytes;
  }

  Future<sqflite.Database> _openDetachedDatabase(String path) async {
    final db = await database.databaseFactory.openDatabase(path);
    await db.execute('PRAGMA foreign_keys = ON');
    return db;
  }

  Future<int> _validateOpenDatabase(sqflite.DatabaseExecutor db) async {
    final schemaVersion = await _schemaVersion(db);
    if (schemaVersion < 1 || schemaVersion > DatabaseMigrations.schemaVersion) {
      throw DataSafetyException(
        'Backup schema version $schemaVersion is not supported.',
      );
    }
    final requiredTables = _requiredTablesFor(schemaVersion);
    final rows = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: 'type = ?',
      whereArgs: ['table'],
    );
    final tableNames = rows.map((row) => row['name'] as String).toSet();
    for (final table in requiredTables) {
      if (!tableNames.contains(table)) {
        throw DataSafetyException('Backup database is missing table "$table".');
      }
    }
    final integrityRows = await db.rawQuery('PRAGMA integrity_check');
    final integrity = integrityRows.isEmpty
        ? null
        : integrityRows.first.values.first?.toString().toLowerCase();
    if (integrity != 'ok') {
      throw const DataSafetyException(
        'Backup database integrity check failed.',
      );
    }
    final foreignKeyRows = await db.rawQuery('PRAGMA foreign_key_check');
    if (foreignKeyRows.isNotEmpty) {
      throw const DataSafetyException(
        'Backup database relationship check failed.',
      );
    }
    return schemaVersion;
  }

  Future<int> _schemaVersion(sqflite.DatabaseExecutor db) async {
    final rows = await db.rawQuery('PRAGMA user_version');
    if (rows.isEmpty) {
      throw const DataSafetyException(
        'Database schema version is unavailable.',
      );
    }
    final value = rows.first.values.first;
    if (value is! int) {
      throw const DataSafetyException('Database schema version is invalid.');
    }
    return value;
  }

  Future<Map<String, int>> _tableCounts(
    sqflite.DatabaseExecutor db, {
    required int schemaVersion,
  }) async {
    final counts = <String, int>{};
    for (final table in _requiredTablesFor(schemaVersion)) {
      final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM $table');
      counts[table] = rows.first['count'] as int;
    }
    return counts;
  }

  Future<List<Map<String, Object?>>> _attachmentRows(
    sqflite.DatabaseExecutor db, {
    required int schemaVersion,
  }) async {
    if (schemaVersion < 4) {
      return const [];
    }
    return db.query('attachments', orderBy: 'created_at ASC, id ASC');
  }

  List<String> _requiredTablesFor(int schemaVersion) {
    if (schemaVersion >= 4) {
      return _allTables;
    }
    if (schemaVersion == 3) {
      return _allTables.take(10).toList();
    }
    if (schemaVersion == 2) {
      return _allTables.take(7).toList();
    }
    return _allTables.take(3).toList();
  }

  Future<List<String>> _columnsFor(
    sqflite.DatabaseExecutor db,
    String table,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return [for (final row in info) row['name'] as String];
  }

  String? _orderByFor(String table) {
    return switch (table) {
      'app_settings' => 'key ASC',
      'service_items' => 'service_id ASC, created_at ASC, id ASC',
      _ => 'created_at ASC, id ASC',
    };
  }

  String _csvFor({
    required List<Map<String, Object?>> rows,
    required List<String> columns,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(columns.map(_csvCell).join(','));
    for (final row in rows) {
      buffer.writeln(columns.map((column) => _csvCell(row[column])).join(','));
    }
    return buffer.toString();
  }

  String _csvCell(Object? value) {
    if (value == null) {
      return '';
    }
    final text = value.toString();
    final escaped = text.replaceAll('"', '""');
    if (escaped.contains(',') ||
        escaped.contains('"') ||
        escaped.contains('\n') ||
        escaped.contains('\r')) {
      return '"$escaped"';
    }
    return escaped;
  }

  Future<int> _databaseFilesSize(String dbPath) async {
    var total = 0;
    for (final path in [dbPath, '$dbPath-wal', '$dbPath-shm']) {
      final file = File(path);
      if (await file.exists()) {
        total += await file.length();
      }
    }
    return total;
  }

  Future<void> _copyCurrentDatabaseToRollback(
    String dbPath,
    Directory rollbackDirectory,
  ) async {
    await rollbackDirectory.create(recursive: true);
    for (final suffix in ['', '-wal', '-shm']) {
      final source = File('$dbPath$suffix');
      if (await source.exists()) {
        await source.copy(
          p.join(rollbackDirectory.path, 'drive_tracker.db$suffix'),
        );
      }
    }
  }

  Future<void> _restoreDatabaseFromRollback(
    String dbPath,
    Directory rollbackDirectory,
  ) async {
    for (final suffix in ['', '-wal', '-shm']) {
      final source = File(
        p.join(rollbackDirectory.path, 'drive_tracker.db$suffix'),
      );
      if (await source.exists()) {
        await source.copy('$dbPath$suffix');
      }
    }
  }

  Future<void> _deleteDatabaseFiles(String dbPath) async {
    for (final path in [dbPath, '$dbPath-wal', '$dbPath-shm']) {
      await _deleteFileBestEffort(File(path));
    }
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    if (!await source.exists()) {
      return;
    }
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final relative = p.relative(entity.path, from: source.path);
      final targetPath = p.join(target.path, relative);
      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
      } else if (entity is File) {
        await File(targetPath).parent.create(recursive: true);
        await entity.copy(targetPath);
      }
    }
  }

  Future<void> _deleteFileBestEffort(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Temporary generated files are safe to leave for OS cleanup.
    }
  }

  Future<Directory> _safetyBackupDirectory() async {
    final dbPath = await database.resolvedPath;
    final directory = Directory(
      p.join(p.dirname(dbPath), 'drive_tracker_safety_backups'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  bool _sameCounts(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  bool _sameStringSet(Set<String> a, Set<String> b) {
    return a.length == b.length && a.every(b.contains);
  }

  String _safeAttachmentPath(String path) {
    final normalized = _normalizeArchivePath(path);
    if (!normalized.startsWith('$attachmentsRoot/')) {
      throw const DataSafetyException('Backup attachment path is invalid.');
    }
    return normalized;
  }

  String _normalizeArchivePath(String path) {
    final value = path.trim();
    if (value.isEmpty ||
        value.contains('\\') ||
        value.contains('\u0000') ||
        value.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(value)) {
      throw const DataSafetyException('Backup contains an unsafe file path.');
    }
    final parts = value.split('/');
    if (parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw const DataSafetyException('Backup contains an unsafe file path.');
    }
    final normalized = p.posix.normalize(value);
    if (normalized != value) {
      throw const DataSafetyException('Backup contains an unsafe file path.');
    }
    return normalized;
  }

  String _timestampedName(String prefix, String extension, DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    final timestamp =
        '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return '$prefix-$timestamp.$extension';
  }

  String _prettyJson(Map<String, Object?> json) {
    return const JsonEncoder.withIndent('  ').convert(json);
  }
}

class _DecodedBackup {
  const _DecodedBackup(this.archive);

  final Archive archive;
}
