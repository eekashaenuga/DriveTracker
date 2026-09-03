import 'package:sqflite/sqflite.dart' as sqflite;

class DatabaseMigrations {
  const DatabaseMigrations._();

  static const schemaVersion = 1;

  static Future<void> createSchema(
    sqflite.DatabaseExecutor db,
    int version,
  ) async {
    if (version != schemaVersion) {
      throw StateError('Unsupported schema version $version.');
    }

    await _createV1(db);
  }

  static Future<void> migrate(
    sqflite.Database db,
    int oldVersion,
    int newVersion,
  ) async {
    for (var version = oldVersion + 1; version <= newVersion; version += 1) {
      switch (version) {
        case schemaVersion:
          await _createV1(db);
          break;
        default:
          throw StateError(
            'No migration registered for schema version $version.',
          );
      }
    }
  }

  static Future<void> _createV1(sqflite.DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE vehicles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        make TEXT NOT NULL,
        model TEXT NOT NULL,
        year INTEGER,
        registration TEXT,
        fuel_type TEXT NOT NULL,
        distance_unit TEXT NOT NULL,
        photo_path TEXT,
        trim TEXT,
        engine TEXT,
        transmission TEXT,
        vin TEXT,
        colour TEXT,
        purchase_date TEXT,
        purchase_mileage INTEGER CHECK (purchase_mileage IS NULL OR purchase_mileage >= 0),
        purchase_price REAL CHECK (purchase_price IS NULL OR purchase_price >= 0),
        seller TEXT,
        notes TEXT,
        is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE odometer_entries (
        id TEXT PRIMARY KEY,
        vehicle_id TEXT NOT NULL,
        odometer INTEGER NOT NULL CHECK (odometer >= 0),
        event_datetime TEXT NOT NULL,
        source_type TEXT NOT NULL,
        source_record_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (vehicle_id) REFERENCES vehicles (id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_vehicles_archived ON vehicles (is_archived)',
    );
    await db.execute('''
      CREATE INDEX idx_odometer_vehicle_reading
      ON odometer_entries (vehicle_id, odometer DESC)
    ''');
    await db.execute('''
      CREATE INDEX idx_odometer_vehicle_event
      ON odometer_entries (vehicle_id, event_datetime DESC)
    ''');
  }
}
