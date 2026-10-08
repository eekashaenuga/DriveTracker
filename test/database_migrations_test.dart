import 'dart:io';

import 'package:drivetracker/core/database/app_database.dart';
import 'package:drivetracker/core/database/database_migrations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('DatabaseMigrations schema validation', () {
    test(
      'accepts every supported schema version created by migrations',
      () async {
        sqfliteFfiInit();
        final dir = await Directory.systemTemp.createTemp(
          'drivetracker_schema_versions_',
        );
        addTearDown(() async {
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        });

        for (final version in [1, 2, 3, 4]) {
          final path = p.join(dir.path, 'schema_v$version.db');
          final db = await databaseFactoryFfi.openDatabase(
            path,
            options: OpenDatabaseOptions(
              version: version,
              onCreate: DatabaseMigrations.createSchema,
            ),
          );
          addTearDown(db.close);

          expect(
            await DatabaseMigrations.validateSchema(
              db,
              expectedVersion: version,
            ),
            version,
          );
        }
      },
    );

    test(
      'upgrades supported databases without losing preferences or vehicles',
      () async {
        sqfliteFfiInit();
        final dir = await Directory.systemTemp.createTemp(
          'dt_upgrade_validation_',
        );
        addTearDown(() => dir.delete(recursive: true));
        for (final version in [1, 2, 3, 4]) {
          final path = p.join(dir.path, 'upgrade_v$version.db');
          final old = await databaseFactoryFfi.openDatabase(
            path,
            options: OpenDatabaseOptions(
              version: version,
              onCreate: DatabaseMigrations.createSchema,
            ),
          );
          await old.insert('vehicles', {
            'id': 'existing',
            'name': 'Existing vehicle',
            'make': 'Ford',
            'model': 'Fiesta',
            'fuel_type': 'petrol',
            'distance_unit': 'miles',
            'created_at': '2026-01-01',
            'updated_at': '2026-01-01',
          });
          await old.insert('app_settings', {
            'key': 'theme_mode',
            'value': 'dark',
            'updated_at': '2026-01-01',
          });
          await old.close();
          final database = AppDatabase(
            databaseFactory: databaseFactoryFfi,
            databasePath: path,
          );
          try {
            final upgraded = await database.database;
            expect(await DatabaseMigrations.validateSchema(upgraded), 4);
            expect(
              (await upgraded.query('vehicles')).single['name'],
              'Existing vehicle',
            );
            expect(
              (await upgraded.query('app_settings')).single['value'],
              'dark',
            );
          } finally {
            await database.close();
          }
        }
      },
    );

    test('rejects a current database with missing schema columns', () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp(
        'drivetracker_incomplete_schema_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });
      final path = p.join(dir.path, 'drive_tracker.db');
      await _writeIncompleteCurrentSchema(path);

      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: path,
      );
      addTearDown(database.close);

      await expectLater(
        database.database,
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            allOf(contains('vehicles'), contains('name')),
          ),
        ),
      );
    });
  });
}

Future<void> _writeIncompleteCurrentSchema(String path) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  try {
    for (final table in DatabaseMigrations.requiredTablesFor(
      DatabaseMigrations.schemaVersion,
    )) {
      await db.execute('CREATE TABLE $table (id TEXT)');
    }
    await db.execute(
      'PRAGMA user_version = ${DatabaseMigrations.schemaVersion}',
    );
  } finally {
    await db.close();
  }
}
