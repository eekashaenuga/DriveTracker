import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drivetracker/app/app_controller.dart';
import 'package:drivetracker/app/theme/dt_theme.dart';
import 'package:drivetracker/core/database/database_migrations.dart';
import 'package:drivetracker/features/attachments/domain/attachment.dart';
import 'package:drivetracker/features/attachments/domain/attachment_io.dart';
import 'package:drivetracker/features/daily_records/domain/expense.dart';
import 'package:drivetracker/features/daily_records/domain/income.dart';
import 'package:drivetracker/features/daily_records/domain/record_category.dart';
import 'package:drivetracker/features/daily_records/domain/refuel.dart';
import 'package:drivetracker/features/data_safety/domain/backup_manifest.dart';
import 'package:drivetracker/features/data_safety/domain/data_safety_service.dart';
import 'package:drivetracker/features/data_safety/presentation/data_storage_screen.dart';
import 'package:drivetracker/features/documents/domain/vehicle_document.dart';
import 'package:drivetracker/features/maintenance/domain/maintenance_item.dart';
import 'package:drivetracker/features/maintenance/domain/service_record.dart';
import 'package:drivetracker/features/more/presentation/more_screen.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'helpers/test_services.dart';

void main() {
  group('AppDatabase snapshots', () {
    test(
      'copies committed data into an independently readable database',
      () async {
        final services = await createFileBackedTestServices();
        await services.vehicleService.addVehicle(
          _vehicleDraft('Snapshot source'),
        );
        final output = await Directory.systemTemp.createTemp('dt_db_snapshot_');
        addTearDown(() async {
          if (await output.exists()) {
            await output.delete(recursive: true);
          }
        });

        final snapshot = File(p.join(output.path, 'snapshot.sqlite'));
        await services.database.copyConsistentSnapshot(snapshot.path);
        final snapshotDb = await services.database.databaseFactory.openDatabase(
          snapshot.path,
        );
        addTearDown(snapshotDb.close);

        expect(
          await _schemaVersionFromDatabase(snapshotDb),
          DatabaseMigrations.schemaVersion,
        );
        expect(await _vehicleNamesFromDatabase(snapshotDb), [
          'Snapshot source',
        ]);

        await services.vehicleService.addVehicle(
          _vehicleDraft('After snapshot'),
        );

        final liveVehicles = await services.vehicles.listActive();
        expect(
          liveVehicles.map((vehicle) => vehicle.name),
          containsAll(['Snapshot source', 'After snapshot']),
        );
        expect(await _vehicleNamesFromDatabase(snapshotDb), [
          'Snapshot source',
        ]);
      },
    );

    test('reopens the live database after a snapshot copy failure', () async {
      final services = await createFileBackedTestServices();
      await services.vehicleService.addVehicle(_vehicleDraft('Before failure'));
      final output = await Directory.systemTemp.createTemp(
        'dt_db_snapshot_failure_',
      );
      addTearDown(() async {
        if (await output.exists()) {
          await output.delete(recursive: true);
        }
      });
      final pathBlocker = File(p.join(output.path, 'not_a_directory'));
      await pathBlocker.writeAsString('blocker', flush: true);

      await expectLater(
        services.database.copyConsistentSnapshot(
          p.join(pathBlocker.path, 'snapshot.sqlite'),
        ),
        throwsA(isA<FileSystemException>()),
      );

      await services.vehicleService.addVehicle(
        _vehicleDraft('After failed snapshot'),
      );
      final vehicles = await services.vehicles.listActive();
      expect(
        vehicles.map((vehicle) => vehicle.name),
        containsAll(['Before failure', 'After failed snapshot']),
      );
    });

    test('supports repeated snapshots without mutating source data', () async {
      final services = await createFileBackedTestServices();
      await services.vehicleService.addVehicle(_vehicleDraft('First'));
      final output = await Directory.systemTemp.createTemp(
        'dt_db_snapshot_repeat_',
      );
      addTearDown(() async {
        if (await output.exists()) {
          await output.delete(recursive: true);
        }
      });

      final firstSnapshot = File(p.join(output.path, 'first.sqlite'));
      final secondSnapshot = File(p.join(output.path, 'second.sqlite'));
      await services.database.copyConsistentSnapshot(firstSnapshot.path);
      await services.vehicleService.addVehicle(_vehicleDraft('Second'));
      await services.database.copyConsistentSnapshot(secondSnapshot.path);

      final firstDb = await services.database.databaseFactory.openDatabase(
        firstSnapshot.path,
      );
      final secondDb = await services.database.databaseFactory.openDatabase(
        secondSnapshot.path,
      );
      addTearDown(firstDb.close);
      addTearDown(secondDb.close);

      expect(await _vehicleNamesFromDatabase(firstDb), ['First']);
      expect(await _vehicleNamesFromDatabase(secondDb), ['First', 'Second']);
      expect(
        await _schemaVersionFromDatabase(secondDb),
        DatabaseMigrations.schemaVersion,
      );

      final liveVehicles = await services.vehicles.listActive();
      expect(
        liveVehicles.map((vehicle) => vehicle.name),
        unorderedEquals(['First', 'Second']),
      );
    });
  });

  group('DataSafetyService', () {
    test(
      'creates a portable backup with manifest database and attachments',
      () async {
        final services = await createFileBackedTestServices();
        final seeded = await _seedSampleData(services);
        final service = _dataSafetyService(services);
        final output = await Directory.systemTemp.createTemp('dt_backup_test_');
        addTearDown(() async {
          if (await output.exists()) {
            await output.delete(recursive: true);
          }
        });

        final backup = await service.createBackup(outputDirectory: output);
        final archive = await _archiveFromFile(backup.file);
        final manifestEntry = archive.find(DataSafetyService.manifestPath);
        final databaseEntry = archive.find(
          DataSafetyService.databaseArchivePath,
        );
        final attachmentEntry = archive.find(seeded.attachment.storedPath);
        final manifest = await _manifestFromArchive(archive);

        expect(manifestEntry, isNotNull);
        expect(databaseEntry, isNotNull);
        expect(attachmentEntry, isNotNull);
        expect(
          manifest.backupFormatVersion,
          DataSafetyService.backupFormatVersion,
        );
        expect(manifest.schemaVersion, DatabaseMigrations.schemaVersion);
        expect(manifest.tableCounts['vehicles'], 1);
        expect(manifest.tableCounts['documents'], 1);
        expect(manifest.attachmentCount, 1);
        expect(
          manifest.attachments.single.storedPath,
          seeded.attachment.storedPath,
        );

        final inspection = await service.inspectBackupFile(backup.file.path);
        expect(inspection.attachmentPaths, [seeded.attachment.storedPath]);
      },
    );

    test(
      'fails backup when a referenced managed attachment is missing',
      () async {
        final services = await createFileBackedTestServices();
        final seeded = await _seedSampleData(services);
        final service = _dataSafetyService(services);
        final missing = File(
          await _storage(services)
              .resolveAbsolutePath(seeded.attachment.storedPath),
        );
        await missing.delete();

        await expectLater(
          service.createBackup(),
          throwsA(isA<DataSafetyException>()),
        );
        await services.vehicleService.addVehicle(
          _vehicleDraft('After failed backup'),
        );
        final vehicles = await services.vehicles.listActive();
        expect(
          vehicles.map((vehicle) => vehicle.name),
          containsAll(['Commuter', 'After failed backup']),
        );
      },
    );

    test(
      'rejects backups with missing unsafe duplicate or mismatched entries',
      () async {
        final services = await createFileBackedTestServices();
        await _seedSampleData(services);
        final service = _dataSafetyService(services);
        final output = await Directory.systemTemp.createTemp(
          'dt_invalid_backup_',
        );
        addTearDown(() async {
          if (await output.exists()) {
            await output.delete(recursive: true);
          }
        });
        final valid = await service.createBackup(outputDirectory: output);
        final validArchive = await _archiveFromFile(valid.file);

        final missingManifest = File(
          p.join(output.path, 'missing_manifest.dtbackup'),
        );
        await _writeArchive(
          missingManifest,
          _archiveWithout(validArchive, {DataSafetyService.manifestPath}),
        );
        await expectLater(
          service.inspectBackupFile(missingManifest.path),
          throwsA(isA<DataSafetyException>()),
        );

        final unsafePath = File(p.join(output.path, 'unsafe_path.dtbackup'));
        await _writeArchive(
          unsafePath,
          _copyArchive(validArchive)
            ..add(ArchiveFile.string('../escape.txt', 'x')),
        );
        await expectLater(
          service.inspectBackupFile(unsafePath.path),
          throwsA(isA<DataSafetyException>()),
        );

        final duplicate = File(p.join(output.path, 'duplicate.dtbackup'));
        await _writeArchiveWithDuplicateManifest(duplicate, validArchive);
        await expectLater(
          service.inspectBackupFile(duplicate.path),
          throwsA(isA<DataSafetyException>()),
        );

        final attachmentPath = (await _manifestFromArchive(validArchive))
            .attachments
            .single
            .storedPath;
        final missingAttachment = File(
          p.join(output.path, 'missing_attachment.dtbackup'),
        );
        await _writeArchive(
          missingAttachment,
          _archiveWithout(validArchive, {attachmentPath}),
        );
        await expectLater(
          service.inspectBackupFile(missingAttachment.path),
          throwsA(isA<DataSafetyException>()),
        );
      },
    );

    test('rejects a backup from a future schema version', () async {
      final services = await createFileBackedTestServices();
      await _seedSampleData(services);
      final service = _dataSafetyService(services);
      final output = await Directory.systemTemp.createTemp('dt_future_backup_');
      addTearDown(() async {
        if (await output.exists()) {
          await output.delete(recursive: true);
        }
      });
      final valid = await service.createBackup(outputDirectory: output);
      final future = File(p.join(output.path, 'future_schema.dtbackup'));
      await _writeFutureSchemaBackup(valid.file, future, services);

      await expectLater(
        service.inspectBackupFile(future.path),
        throwsA(isA<DataSafetyException>()),
      );
    });

    test('restores database and managed attachments from backup', () async {
      final services = await createFileBackedTestServices();
      final seeded = await _seedSampleData(services, vehicleName: 'Original');
      final service = _dataSafetyService(services);
      final output = await Directory.systemTemp.createTemp(
        'dt_restore_backup_',
      );
      addTearDown(() async {
        if (await output.exists()) {
          await output.delete(recursive: true);
        }
      });
      final backup = await service.createBackup(outputDirectory: output);
      await services.vehicleService.addVehicle(_vehicleDraft('Temporary'));

      final result = await service.restoreBackupFromFile(backup.file.path);
      final vehicles = await services.vehicles.listActive();
      final restoredAttachment = File(
        await _storage(services)
            .resolveAbsolutePath(seeded.attachment.storedPath),
      );

      expect(vehicles.map((vehicle) => vehicle.name), ['Original']);
      expect(await restoredAttachment.exists(), isTrue);
      expect(await File(result.safetyBackupPath).exists(), isTrue);
    });

    test(
      'aborts restore before destructive changes if safety backup fails',
      () async {
        final services = await createFileBackedTestServices();
        await _seedSampleData(services, vehicleName: 'Original');
        final output = await Directory.systemTemp.createTemp(
          'dt_safety_failure_',
        );
        addTearDown(() async {
          if (await output.exists()) {
            await output.delete(recursive: true);
          }
        });
        final backup = await _dataSafetyService(services)
            .createBackup(outputDirectory: output);
        await services.vehicleService.addVehicle(_vehicleDraft('Current'));
        final failing = _dataSafetyService(
          services,
          beforeSafetyBackup: () async {
            throw const DataSafetyException('Safety backup unavailable.');
          },
        );

        await expectLater(
          failing.restoreBackupFromFile(backup.file.path),
          throwsA(isA<DataSafetyException>()),
        );
        final vehicles = await services.vehicles.listActive();
        expect(vehicles.map((vehicle) => vehicle.name), contains('Current'));
      },
    );

    test(
      'reopens current data if safety backup packaging fails after snapshot',
      () async {
        final services = await createFileBackedTestServices();
        final seeded = await _seedSampleData(services, vehicleName: 'Original');
        final output = await Directory.systemTemp.createTemp(
          'dt_safety_package_failure_',
        );
        addTearDown(() async {
          if (await output.exists()) {
            await output.delete(recursive: true);
          }
        });
        final backup = await _dataSafetyService(services)
            .createBackup(outputDirectory: output);
        await services.vehicleService.addVehicle(_vehicleDraft('Current'));
        final missing = File(
          await _storage(services)
              .resolveAbsolutePath(seeded.attachment.storedPath),
        );
        await missing.delete();

        await expectLater(
          _dataSafetyService(services).restoreBackupFromFile(backup.file.path),
          throwsA(isA<DataSafetyException>()),
        );
        await services.vehicleService.addVehicle(
          _vehicleDraft('After failed safety backup'),
        );
        final vehicles = await services.vehicles.listActive();
        expect(
          vehicles.map((vehicle) => vehicle.name),
          containsAll(['Current', 'After failed safety backup']),
        );
      },
    );

    test('rolls back current data if staged restore install fails', () async {
      final services = await createFileBackedTestServices();
      await _seedSampleData(services, vehicleName: 'Original');
      final output = await Directory.systemTemp.createTemp('dt_rollback_');
      addTearDown(() async {
        if (await output.exists()) {
          await output.delete(recursive: true);
        }
      });
      final backup = await _dataSafetyService(services)
          .createBackup(outputDirectory: output);
      await services.vehicleService.addVehicle(_vehicleDraft('Keep me'));
      final failing = _dataSafetyService(
        services,
        afterDatabaseInstall: () async {
          throw StateError('Injected restore failure');
        },
      );

      await expectLater(
        failing.restoreBackupFromFile(backup.file.path),
        throwsA(isA<DataSafetyException>()),
      );
      final vehicles = await services.vehicles.listActive();
      expect(vehicles.map((vehicle) => vehicle.name), contains('Keep me'));
    });

    test('exports current data as a CSV zip package', () async {
      final services = await createFileBackedTestServices();
      await _seedSampleData(services);
      final service = _dataSafetyService(services);
      final output = await Directory.systemTemp.createTemp('dt_csv_export_');
      addTearDown(() async {
        if (await output.exists()) {
          await output.delete(recursive: true);
        }
      });

      final export = await service.createCsvExport(outputDirectory: output);
      final archive = await _archiveFromFile(export.file);
      final vehiclesCsv = utf8.decode(
        archive.find('csv/vehicles.csv')!.readBytes()!,
      );
      final attachmentsCsv = utf8.decode(
        archive.find('csv/attachments.csv')!.readBytes()!,
      );

      expect(archive.find('README.txt'), isNotNull);
      expect(vehiclesCsv, contains('Commuter'));
      expect(attachmentsCsv, contains('policy.pdf'));
    });
  });

  group('DriveTrackerController restore lifecycle', () {
    test('reloads cached state after successful restore', () async {
      final services = await createFileBackedTestServices();
      await _seedSampleData(services, vehicleName: 'Original');
      final output = await Directory.systemTemp.createTemp(
        'dt_controller_restore_',
      );
      addTearDown(() async {
        if (await output.exists()) {
          await output.delete(recursive: true);
        }
      });
      final backup = await _dataSafetyService(services)
          .createBackup(outputDirectory: output);
      final controller = _controller(services, FakeDataSafetyFileBridge());
      await controller.initialize();
      await controller.addVehicle(_vehicleDraft('Remove me'));

      expect(
        controller.activeVehicles.map((vehicle) => vehicle.name),
        contains('Remove me'),
      );

      await controller.restoreBackupFromFile(backup.file.path);

      expect(controller.activeVehicles.map((vehicle) => vehicle.name), [
        'Original',
      ]);
      expect(controller.selectedVehicle?.name, 'Original');
      final documents = await controller.documentsForSelectedVehicle();
      expect(documents.map((document) => document.title), ['Policy schedule']);
    });

    test('reconciles state after failed restore safety backup', () async {
      final services = await createFileBackedTestServices();
      final seeded = await _seedSampleData(services, vehicleName: 'Original');
      final output = await Directory.systemTemp.createTemp(
        'dt_controller_restore_failure_',
      );
      addTearDown(() async {
        if (await output.exists()) {
          await output.delete(recursive: true);
        }
      });
      final backup = await _dataSafetyService(services)
          .createBackup(outputDirectory: output);
      final controller = _controller(services, FakeDataSafetyFileBridge());
      await controller.initialize();
      await controller.addVehicle(_vehicleDraft('Current'));
      final missing = File(
        await _storage(services)
            .resolveAbsolutePath(seeded.attachment.storedPath),
      );
      await missing.delete();

      await expectLater(
        controller.restoreBackupFromFile(backup.file.path),
        throwsA(isA<DataSafetyException>()),
      );

      expect(
        controller.activeVehicles.map((vehicle) => vehicle.name),
        contains('Current'),
      );
      await controller.addVehicle(_vehicleDraft('After failed restore'));
      expect(
        controller.activeVehicles.map((vehicle) => vehicle.name),
        containsAll(['Current', 'After failed restore']),
      );
    });
  });

  group('Data & Storage screen', () {
    testWidgets('is reachable from More', (tester) async {
      final services = await _createWidgetServices(tester);
      await tester.runAsync(
        () => services.vehicleService.addVehicle(_vehicleDraft('Commuter')),
      );
      final bridge = FakeDataSafetyFileBridge();
      final controller = _controller(services, bridge);

      await tester.runAsync(controller.initialize);
      await tester.pumpWidget(
        ChangeNotifierProvider<DriveTrackerController>.value(
          value: controller,
          child: MaterialApp(theme: DTTheme.light(), home: const MoreScreen()),
        ),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('moreDataStorageTile')),
      );
      await tester.tap(find.byKey(const Key('moreDataStorageTile')));
      await _pumpUntilFound(tester, find.byKey(const Key('dataStorageLoaded')));

      expect(find.byType(DataStorageScreen), findsOneWidget);
      expect(find.byKey(const Key('dataStorageLoaded')), findsOneWidget);
    });

    testWidgets('saves backup and CSV export through the file bridge', (
      tester,
    ) async {
      final services = await _createWidgetServices(tester);
      await tester.runAsync(() => _seedSampleData(services));
      final bridge = FakeDataSafetyFileBridge();

      await _pumpDataStorage(tester, services, bridge);
      await _tapAndRunAsync(
        tester,
        find.byKey(const Key('dataStorageBackupButton')),
      );
      await _pumpUntil(tester, () => bridge.savedFiles.length == 1);
      await tester.drag(find.byType(ListView), const Offset(0, -260));
      await tester.pump();
      await _tapAndRunAsync(
        tester,
        find.byKey(const Key('dataStorageExportCsvButton')),
      );
      await _pumpUntil(tester, () => bridge.savedFiles.length == 2);

      expect(bridge.savedFiles.map((file) => file.suggestedName), [
        startsWith('drivetracker-backup-'),
        startsWith('drivetracker-csv-export-'),
      ]);
      expect(bridge.savedFiles.first.suggestedName, endsWith('.dtbackup'));
      expect(
        bridge.savedFiles.first.mimeType,
        DataSafetyService.backupMimeType,
      );
      final backupCopyExists = await _runWidgetAsync(
        tester,
        () => File(bridge.savedFiles.first.savedPath).exists(),
      );
      expect(backupCopyExists, isTrue);
      expect(bridge.savedFiles.last.suggestedName, endsWith('.zip'));
      expect(
        bridge.savedFiles.last.mimeType,
        DataSafetyService.csvExportMimeType,
      );
    });

    testWidgets('cancelled restore leaves current data untouched', (
      tester,
    ) async {
      final services = await _createWidgetServices(tester);
      await tester.runAsync(
        () => _seedSampleData(services, vehicleName: 'Original'),
      );
      final output = await _createWidgetTempDirectory(
        tester,
        'dt_restore_cancel_',
      );
      addTearDown(() async {
        if (await output.exists()) {
          await output.delete(recursive: true);
        }
      });
      final backup = await _runWidgetAsync(
        tester,
        () =>
            _dataSafetyService(services).createBackup(outputDirectory: output),
      );
      await tester.runAsync(
        () => services.vehicleService.addVehicle(_vehicleDraft('Still here')),
      );
      final bridge = FakeDataSafetyFileBridge()
        ..nextBackup = PickedBackupFile(
          sourcePath: backup.file.path,
          fileName: backup.suggestedName,
        );

      await _pumpDataStorage(tester, services, bridge);
      await _tapAndRunAsync(
        tester,
        find.byKey(const Key('dataStorageRestoreButton')),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('restoreBackupConfirmDialog')),
      );
      expect(
        find.byKey(const Key('restoreBackupConfirmDialog')),
        findsOneWidget,
      );
      await _tapAndRunAsync(
        tester,
        find.byKey(const Key('cancelRestoreBackupButton')),
      );
      await tester.pump();

      final vehicles = await _runWidgetAsync(
        tester,
        services.vehicles.listActive,
      );
      expect(vehicles.map((vehicle) => vehicle.name), contains('Still here'));
    });

    testWidgets('confirmed restore applies the selected backup', (
      tester,
    ) async {
      final services = await _createWidgetServices(tester);
      await tester.runAsync(
        () => _seedSampleData(services, vehicleName: 'Original'),
      );
      final output = await _createWidgetTempDirectory(
        tester,
        'dt_restore_confirm_',
      );
      addTearDown(() async {
        if (await output.exists()) {
          await output.delete(recursive: true);
        }
      });
      final backup = await _runWidgetAsync(
        tester,
        () =>
            _dataSafetyService(services).createBackup(outputDirectory: output),
      );
      await tester.runAsync(
        () => services.vehicleService.addVehicle(_vehicleDraft('Remove me')),
      );
      final bridge = FakeDataSafetyFileBridge()
        ..nextBackup = PickedBackupFile(
          sourcePath: backup.file.path,
          fileName: backup.suggestedName,
        );

      await _pumpDataStorage(tester, services, bridge);
      await _tapAndRunAsync(
        tester,
        find.byKey(const Key('dataStorageRestoreButton')),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('restoreBackupConfirmDialog')),
      );
      await _tapAndRunAsync(
        tester,
        find.byKey(const Key('confirmRestoreBackupButton')),
      );
      await _pumpUntil(
        tester,
        () => tester.any(find.textContaining('Restore complete')),
      );

      final vehicles = await _runWidgetAsync(
        tester,
        services.vehicles.listActive,
      );
      expect(vehicles.map((vehicle) => vehicle.name), ['Original']);
    });

    testWidgets('renders on a narrow dark Android-sized surface', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final services = await _createWidgetServices(tester);
      await tester.runAsync(() => _seedSampleData(services));
      final bridge = FakeDataSafetyFileBridge();

      await _pumpDataStorage(
        tester,
        services,
        bridge,
        themeMode: ThemeMode.dark,
      );

      expect(find.byKey(const Key('dataStorageLoaded')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

DataSafetyService _dataSafetyService(
  TestServices services, {
  DataSafetyFileBridge? bridge,
  Future<void> Function()? beforeSafetyBackup,
  Future<void> Function()? afterDatabaseInstall,
}) {
  return DataSafetyService(
    database: services.database,
    attachmentStorage: _storage(services),
    fileBridge: bridge ?? FakeDataSafetyFileBridge(),
    clock: () => DateTime.utc(2026, 9, 10, 12),
    beforeSafetyBackup: beforeSafetyBackup,
    afterDatabaseInstall: afterDatabaseInstall,
  );
}

DriveTrackerController _controller(
  TestServices services,
  DataSafetyFileBridge bridge,
) {
  return DriveTrackerController(
    database: services.database,
    attachmentStorage: _storage(services),
    attachmentPicker: services.attachmentPicker,
    attachmentOpener: services.attachmentOpener,
    dataSafetyFileBridge: bridge,
    clock: () => DateTime.utc(2026, 9, 10, 12),
  );
}

Future<void> _pumpDataStorage(
  WidgetTester tester,
  TestServices services,
  FakeDataSafetyFileBridge bridge, {
  ThemeMode themeMode = ThemeMode.light,
}) async {
  final controller = _controller(services, bridge);
  await tester.runAsync(controller.initialize);
  await tester.pumpWidget(
    ChangeNotifierProvider<DriveTrackerController>.value(
      value: controller,
      child: MaterialApp(
        theme: DTTheme.light(),
        darkTheme: DTTheme.dark(),
        themeMode: themeMode,
        home: const DataStorageScreen(),
      ),
    ),
  );
  await _pumpUntilFound(tester, find.byKey(const Key('dataStorageLoaded')));
}

Future<TestServices> _createWidgetServices(WidgetTester tester) {
  return _runWidgetAsync(tester, createFileBackedTestServices);
}

Future<Directory> _createWidgetTempDirectory(
  WidgetTester tester,
  String prefix,
) {
  return _runWidgetAsync(tester, () => Directory.systemTemp.createTemp(prefix));
}

Future<T> _runWidgetAsync<T>(
  WidgetTester tester,
  Future<T> Function() action,
) async {
  final result = await tester.runAsync(action);
  if (result == null) {
    fail('Expected widget async operation to return a value.');
  }
  return result;
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 80,
}) {
  return _pumpUntil(tester, () => tester.any(finder), attempts: attempts);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 80,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    if (condition()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    if (condition()) {
      return;
    }
  }
  expect(condition(), isTrue);
}

Future<void> _tapAndRunAsync(WidgetTester tester, Finder finder) async {
  await _pumpUntilFound(tester, finder);
  final target = finder.hitTestable();
  await tester.runAsync(() async {
    await tester.tap(target.evaluate().isEmpty ? finder : target);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
  await tester.pump();
}

ManagedAttachmentStorage _storage(TestServices services) {
  return ManagedAttachmentStorage(
    rootDirectory: () async => services.attachmentRoot,
  );
}

Future<_SeededData> _seedSampleData(
  TestServices services, {
  String vehicleName = 'Commuter',
}) async {
  final vehicle = await services.vehicleService.addVehicle(
    _vehicleDraft(vehicleName),
  );
  final expenseCategory = await services.categories.findByTypeAndName(
    RecordCategoryType.expense,
    'Parking',
  );
  final incomeCategory = await services.categories.findByTypeAndName(
    RecordCategoryType.income,
    'Delivery',
  );
  await services.refuelService.createRefuel(
    RefuelDraft(
      vehicleId: vehicle.id,
      eventDateTime: DateTime.utc(2026, 2, 1, 9),
      odometer: 10100,
      fuelType: FuelType.petrol,
      totalCostMinor: 5000,
      volumeMillilitres: 40000,
      unitPriceMicrosPerLitre: 1250000,
      isFullTank: true,
      missedPreviousRefuel: false,
      station: 'Shell',
    ),
    confirmLargeIncrease: true,
  );
  await services.expenseService.createExpense(
    ExpenseDraft(
      vehicleId: vehicle.id,
      categoryId: expenseCategory!.id,
      eventDateTime: DateTime.utc(2026, 2, 2, 9),
      amountMinor: 600,
      odometer: 10120,
      merchant: 'Town car park',
    ),
  );
  await services.incomeService.createIncome(
    IncomeDraft(
      vehicleId: vehicle.id,
      categoryId: incomeCategory!.id,
      eventDateTime: DateTime.utc(2026, 2, 3, 9),
      amountMinor: 2200,
      source: 'Courier shift',
    ),
  );
  final maintenanceItem = await services.maintenanceItemService
      .createMaintenanceItem(
        MaintenanceItemDraft(
          vehicleId: vehicle.id,
          name: 'Oil change',
          category: 'Engine',
          mileageInterval: 6000,
        ),
      );
  await services.serviceRecordService.createServiceRecord(
    ServiceRecordDraft(
      vehicleId: vehicle.id,
      eventDateTime: DateTime.utc(2026, 2, 4, 9),
      odometer: 10200,
      totalCostMinor: 12999,
      garage: 'Local Garage',
      items: [
        ServiceItemDraft(
          maintenanceItemId: maintenanceItem.id,
          itemName: maintenanceItem.name,
          allocatedCostMinor: 12999,
        ),
      ],
    ),
  );
  final document = await services.documentService.createDocument(
    VehicleDocumentDraft(
      vehicleId: vehicle.id,
      category: 'Insurance',
      title: 'Policy schedule',
      expiryDate: DateTime(2027, 9, 1),
      provider: 'Admiral',
    ),
  );
  final sourceFile = await _writeSourceFile(services, 'policy.pdf', [
    1,
    2,
    3,
    4,
  ]);
  final attachment = await services.attachmentService.addAttachment(
    parentType: AttachmentParentType.document,
    parentId: document.id,
    source: AttachmentSource(
      sourcePath: sourceFile.path,
      fileName: 'policy.pdf',
      mimeType: 'application/pdf',
      fileSize: await sourceFile.length(),
    ),
  );
  return _SeededData(attachment: attachment);
}

VehicleDraft _vehicleDraft(String name) {
  return VehicleDraft(
    name: name,
    make: 'Toyota',
    model: 'Corolla',
    currentOdometer: 10000,
    fuelType: FuelType.petrol,
    distanceUnit: DistanceUnit.miles,
  );
}

Future<File> _writeSourceFile(
  TestServices services,
  String name,
  List<int> bytes,
) async {
  final file = File(p.join(services.attachmentRoot.path, 'sources', name));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<Archive> _archiveFromFile(File file) async {
  return ZipDecoder().decodeBytes(await file.readAsBytes());
}

Future<BackupManifest> _manifestFromArchive(Archive archive) async {
  final entry = archive.find(DataSafetyService.manifestPath);
  expect(entry, isNotNull);
  final decoded = jsonDecode(utf8.decode(entry!.readBytes()!));
  return BackupManifest.fromJson(Map<String, Object?>.from(decoded as Map));
}

Archive _copyArchive(Archive archive) {
  final copy = Archive();
  for (final entry in archive) {
    if (entry.isFile) {
      copy.add(ArchiveFile.bytes(entry.name, entry.readBytes()!));
    }
  }
  return copy;
}

Archive _archiveWithout(Archive archive, Set<String> excludedNames) {
  final copy = Archive();
  for (final entry in archive) {
    if (entry.isFile && !excludedNames.contains(entry.name)) {
      copy.add(ArchiveFile.bytes(entry.name, entry.readBytes()!));
    }
  }
  return copy;
}

Future<void> _writeArchive(File file, Archive archive) async {
  await file.writeAsBytes(ZipEncoder().encodeBytes(archive), flush: true);
}

Future<void> _writeArchiveWithDuplicateManifest(
  File file,
  Archive archive,
) async {
  final encoder = ZipFileEncoder()..create(file.path);
  for (final entry in archive) {
    if (entry.isFile) {
      encoder.addArchiveFile(ArchiveFile.bytes(entry.name, entry.readBytes()!));
    }
  }
  encoder.addArchiveFile(
    ArchiveFile.string(DataSafetyService.manifestPath, '{}'),
  );
  await encoder.close();
}

Future<void> _writeFutureSchemaBackup(
  File sourceBackup,
  File futureBackup,
  TestServices services,
) async {
  final archive = await _archiveFromFile(sourceBackup);
  final output = Archive();
  final tempDir = await Directory.systemTemp.createTemp('dt_future_db_');
  addTearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });
  final databaseFile = File(p.join(tempDir.path, 'database.sqlite'));
  await databaseFile.writeAsBytes(
    archive.find(DataSafetyService.databaseArchivePath)!.readBytes()!,
    flush: true,
  );
  final db = await services.database.databaseFactory.openDatabase(
    databaseFile.path,
  );
  await db.execute(
    'PRAGMA user_version = ${DatabaseMigrations.schemaVersion + 1}',
  );
  await db.close();
  final manifest = await _manifestFromArchive(archive);
  final json = manifest.toJson()
    ..['schemaVersion'] = DatabaseMigrations.schemaVersion + 1;
  for (final entry in archive) {
    if (!entry.isFile) {
      continue;
    }
    if (entry.name == DataSafetyService.databaseArchivePath) {
      output.add(
        ArchiveFile.bytes(entry.name, await databaseFile.readAsBytes()),
      );
    } else if (entry.name == DataSafetyService.manifestPath) {
      output.add(
        ArchiveFile.string(entry.name, const JsonEncoder().convert(json)),
      );
    } else {
      output.add(ArchiveFile.bytes(entry.name, entry.readBytes()!));
    }
  }
  await _writeArchive(futureBackup, output);
}

Future<List<String>> _vehicleNamesFromDatabase(
  sqflite.DatabaseExecutor database,
) async {
  final rows = await database.query(
    'vehicles',
    columns: ['name'],
    orderBy: 'created_at ASC, id ASC',
  );
  return rows.map((row) => row['name'] as String).toList();
}

Future<int> _schemaVersionFromDatabase(
  sqflite.DatabaseExecutor database,
) async {
  final rows = await database.rawQuery('PRAGMA user_version');
  expect(rows, isNotEmpty);
  final version = rows.first.values.first;
  expect(version, isA<int>());
  return version as int;
}

class FakeDataSafetyFileBridge implements DataSafetyFileBridge {
  FakeDataSafetyFileBridge() {
    addTearDown(() async {
      if (await _savedDirectory.exists()) {
        await _savedDirectory.delete(recursive: true);
      }
    });
  }

  final Directory _savedDirectory = Directory.systemTemp.createTempSync(
    'dt_saved_files_',
  );
  final savedFiles = <_SavedFile>[];
  PickedBackupFile? nextBackup;
  bool cancelSave = false;

  @override
  Future<PickedBackupFile?> pickBackupFile() async {
    final picked = nextBackup;
    nextBackup = null;
    return picked;
  }

  @override
  Future<DataSafetyFileSaveResult> saveFile({
    required String sourcePath,
    required String suggestedName,
    required String mimeType,
  }) async {
    if (cancelSave) {
      return const DataSafetyFileSaveResult(DataSafetyFileSaveStatus.cancelled);
    }
    final saved = File(p.join(_savedDirectory.path, suggestedName));
    await File(sourcePath).copy(saved.path);
    savedFiles.add(
      _SavedFile(
        savedPath: saved.path,
        suggestedName: suggestedName,
        mimeType: mimeType,
      ),
    );
    return DataSafetyFileSaveResult(
      DataSafetyFileSaveStatus.saved,
      displayName: suggestedName,
    );
  }
}

class _SavedFile {
  const _SavedFile({
    required this.savedPath,
    required this.suggestedName,
    required this.mimeType,
  });

  final String savedPath;
  final String suggestedName;
  final String mimeType;
}

class _SeededData {
  const _SeededData({required this.attachment});

  final Attachment attachment;
}
