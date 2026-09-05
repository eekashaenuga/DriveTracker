import 'package:sqflite/sqflite.dart' as sqflite;

class DatabaseMigrations {
  const DatabaseMigrations._();

  static const schemaVersion = 2;

  static Future<void> createSchema(
    sqflite.DatabaseExecutor db,
    int version,
  ) async {
    if (version < 1 || version > schemaVersion) {
      throw StateError('Unsupported schema version $version.');
    }

    await _createV1(db);
    if (version >= 2) {
      await _createV2(db);
    }
  }

  static Future<void> migrate(
    sqflite.Database db,
    int oldVersion,
    int newVersion,
  ) async {
    for (var version = oldVersion + 1; version <= newVersion; version += 1) {
      switch (version) {
        case 2:
          await _createV2(db);
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

  static Future<void> _createV2(sqflite.DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE record_categories (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL CHECK (type IN ('EXPENSE', 'INCOME', 'MAINTENANCE')),
        name TEXT NOT NULL,
        icon_identifier TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        system_category INTEGER NOT NULL DEFAULT 0 CHECK (system_category IN (0, 1)),
        is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (type, name)
      )
    ''');

    await db.execute('''
      CREATE TABLE refuels (
        id TEXT PRIMARY KEY,
        vehicle_id TEXT NOT NULL,
        event_datetime TEXT NOT NULL,
        odometer INTEGER NOT NULL CHECK (odometer >= 0),
        fuel_type TEXT NOT NULL,
        total_cost_minor INTEGER NOT NULL CHECK (total_cost_minor > 0),
        volume_millilitres INTEGER NOT NULL CHECK (volume_millilitres > 0),
        unit_price_micros_per_litre INTEGER NOT NULL CHECK (unit_price_micros_per_litre > 0),
        is_full_tank INTEGER NOT NULL CHECK (is_full_tank IN (0, 1)),
        missed_previous_refuel INTEGER NOT NULL CHECK (missed_previous_refuel IN (0, 1)),
        station TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (vehicle_id) REFERENCES vehicles (id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id TEXT PRIMARY KEY,
        vehicle_id TEXT NOT NULL,
        category_id TEXT NOT NULL,
        event_datetime TEXT NOT NULL,
        odometer INTEGER CHECK (odometer IS NULL OR odometer >= 0),
        amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
        merchant TEXT,
        payment_method TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (vehicle_id) REFERENCES vehicles (id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT,
        FOREIGN KEY (category_id) REFERENCES record_categories (id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE income_records (
        id TEXT PRIMARY KEY,
        vehicle_id TEXT NOT NULL,
        category_id TEXT NOT NULL,
        event_datetime TEXT NOT NULL,
        odometer INTEGER CHECK (odometer IS NULL OR odometer >= 0),
        amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
        source TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (vehicle_id) REFERENCES vehicles (id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT,
        FOREIGN KEY (category_id) REFERENCES record_categories (id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX idx_odometer_source_record
      ON odometer_entries (source_type, source_record_id)
      WHERE source_record_id IS NOT NULL
    ''');
    await db.execute('''
      CREATE INDEX idx_categories_type_archived
      ON record_categories (type, is_archived, sort_order)
    ''');
    await db.execute('''
      CREATE INDEX idx_refuels_vehicle_event
      ON refuels (vehicle_id, event_datetime DESC)
    ''');
    await db.execute('''
      CREATE INDEX idx_refuels_vehicle_odometer
      ON refuels (vehicle_id, odometer)
    ''');
    await db.execute('''
      CREATE INDEX idx_expenses_vehicle_event
      ON expenses (vehicle_id, event_datetime DESC)
    ''');
    await db.execute('''
      CREATE INDEX idx_expenses_category
      ON expenses (category_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_income_vehicle_event
      ON income_records (vehicle_id, event_datetime DESC)
    ''');
    await db.execute('''
      CREATE INDEX idx_income_category
      ON income_records (category_id)
    ''');

    await _seedDefaultCategories(db);
  }

  static Future<void> _seedDefaultCategories(
    sqflite.DatabaseExecutor db,
  ) async {
    const timestamp = '2026-01-01T00:00:00.000Z';
    const categories = [
      ('cat_expense_insurance', 'EXPENSE', 'Insurance', 'shield', 10),
      ('cat_expense_tax', 'EXPENSE', 'Tax', 'receipt_long', 20),
      ('cat_expense_mot', 'EXPENSE', 'MOT', 'verified', 30),
      ('cat_expense_parking', 'EXPENSE', 'Parking', 'local_parking', 40),
      ('cat_expense_toll', 'EXPENSE', 'Toll', 'toll', 50),
      ('cat_expense_repair', 'EXPENSE', 'Repair', 'build', 60),
      ('cat_expense_parts', 'EXPENSE', 'Parts', 'car_repair', 70),
      ('cat_expense_cleaning', 'EXPENSE', 'Cleaning', 'local_car_wash', 80),
      ('cat_expense_fine', 'EXPENSE', 'Fine', 'gavel', 90),
      ('cat_expense_subscription', 'EXPENSE', 'Subscription', 'payments', 100),
      ('cat_expense_other', 'EXPENSE', 'Other', 'more_horiz', 110),
      ('cat_income_rideshare', 'INCOME', 'Rideshare', 'hail', 10),
      ('cat_income_delivery', 'INCOME', 'Delivery', 'delivery_dining', 20),
      (
        'cat_income_mileage_reimbursement',
        'INCOME',
        'Mileage reimbursement',
        'route',
        30,
      ),
      ('cat_income_rental', 'INCOME', 'Rental', 'key', 40),
      ('cat_income_vehicle_sale', 'INCOME', 'Vehicle sale', 'sell', 50),
      ('cat_income_other', 'INCOME', 'Other', 'more_horiz', 60),
    ];

    for (final category in categories) {
      await db.insert('record_categories', {
        'id': category.$1,
        'type': category.$2,
        'name': category.$3,
        'icon_identifier': category.$4,
        'sort_order': category.$5,
        'system_category': 1,
        'is_archived': 0,
        'created_at': timestamp,
        'updated_at': timestamp,
      }, conflictAlgorithm: sqflite.ConflictAlgorithm.ignore);
    }
  }
}
