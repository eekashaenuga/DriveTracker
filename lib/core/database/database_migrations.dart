import 'package:sqflite/sqflite.dart' as sqflite;

class DatabaseMigrations {
  const DatabaseMigrations._();

  static const schemaVersion = 4;

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

  static const _requiredColumnsByTable = <String, List<String>>{
    'vehicles': [
      'id',
      'name',
      'make',
      'model',
      'year',
      'registration',
      'fuel_type',
      'distance_unit',
      'photo_path',
      'trim',
      'engine',
      'transmission',
      'vin',
      'colour',
      'purchase_date',
      'purchase_mileage',
      'purchase_price',
      'seller',
      'notes',
      'is_archived',
      'created_at',
      'updated_at',
    ],
    'odometer_entries': [
      'id',
      'vehicle_id',
      'odometer',
      'event_datetime',
      'source_type',
      'source_record_id',
      'created_at',
      'updated_at',
    ],
    'app_settings': ['key', 'value', 'updated_at'],
    'record_categories': [
      'id',
      'type',
      'name',
      'icon_identifier',
      'sort_order',
      'system_category',
      'is_archived',
      'created_at',
      'updated_at',
    ],
    'refuels': [
      'id',
      'vehicle_id',
      'event_datetime',
      'odometer',
      'fuel_type',
      'total_cost_minor',
      'volume_millilitres',
      'unit_price_micros_per_litre',
      'is_full_tank',
      'missed_previous_refuel',
      'station',
      'notes',
      'created_at',
      'updated_at',
    ],
    'expenses': [
      'id',
      'vehicle_id',
      'category_id',
      'event_datetime',
      'odometer',
      'amount_minor',
      'merchant',
      'payment_method',
      'notes',
      'created_at',
      'updated_at',
    ],
    'income_records': [
      'id',
      'vehicle_id',
      'category_id',
      'event_datetime',
      'odometer',
      'amount_minor',
      'source',
      'notes',
      'created_at',
      'updated_at',
    ],
    'maintenance_items': [
      'id',
      'vehicle_id',
      'name',
      'category',
      'mileage_interval',
      'time_interval_days',
      'mileage_warning',
      'date_warning_days',
      'reminder_enabled',
      'is_archived',
      'created_at',
      'updated_at',
    ],
    'services': [
      'id',
      'vehicle_id',
      'event_datetime',
      'odometer',
      'total_cost_minor',
      'garage',
      'notes',
      'is_baseline',
      'created_at',
      'updated_at',
    ],
    'service_items': [
      'id',
      'service_id',
      'maintenance_item_id',
      'item_name',
      'allocated_cost_minor',
      'notes',
      'created_at',
      'updated_at',
    ],
    'documents': [
      'id',
      'vehicle_id',
      'category',
      'title',
      'issue_date',
      'expiry_date',
      'reference_number',
      'provider',
      'notes',
      'reminder_id',
      'is_archived',
      'archived_at',
      'created_at',
      'updated_at',
    ],
    'attachments': [
      'id',
      'parent_type',
      'parent_id',
      'file_name',
      'stored_path',
      'mime_type',
      'file_size',
      'created_at',
      'updated_at',
    ],
  };

  static const _allIndexes = [
    'idx_vehicles_archived',
    'idx_odometer_vehicle_reading',
    'idx_odometer_vehicle_event',
    'idx_odometer_source_record',
    'idx_categories_type_archived',
    'idx_refuels_vehicle_event',
    'idx_refuels_vehicle_odometer',
    'idx_expenses_vehicle_event',
    'idx_expenses_category',
    'idx_income_vehicle_event',
    'idx_income_category',
    'idx_maintenance_items_vehicle_active',
    'idx_maintenance_items_active_name',
    'idx_services_vehicle_event',
    'idx_services_vehicle_odometer',
    'idx_service_items_service',
    'idx_service_items_maintenance_item',
    'idx_documents_vehicle_active_expiry',
    'idx_documents_vehicle_category',
    'idx_attachments_parent',
    'idx_attachments_stored_path',
  ];

  static List<String> requiredTablesFor(int version) {
    _checkSupportedVersion(version);
    if (version >= 4) {
      return _allTables;
    }
    if (version == 3) {
      return _allTables.take(10).toList();
    }
    if (version == 2) {
      return _allTables.take(7).toList();
    }
    return _allTables.take(3).toList();
  }

  static List<String> requiredIndexesFor(int version) {
    _checkSupportedVersion(version);
    if (version >= 4) {
      return _allIndexes;
    }
    if (version == 3) {
      return _allIndexes.take(17).toList();
    }
    if (version == 2) {
      return _allIndexes.take(11).toList();
    }
    return _allIndexes.take(3).toList();
  }

  static Future<int> readSchemaVersion(sqflite.DatabaseExecutor db) async {
    final rows = await db.rawQuery('PRAGMA user_version');
    if (rows.isEmpty) {
      throw StateError('SQLite schema version could not be read.');
    }
    final value = rows.first.values.first;
    if (value is! int) {
      throw StateError('SQLite schema version is invalid.');
    }
    return value;
  }

  static Future<int> validateSchema(
    sqflite.DatabaseExecutor db, {
    int? expectedVersion,
  }) async {
    final version = await readSchemaVersion(db);
    if (expectedVersion != null && version != expectedVersion) {
      throw StateError(
        'SQLite schema version $version does not match expected version '
        '$expectedVersion.',
      );
    }
    _checkSupportedVersion(version);

    final tableRows = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: 'type = ?',
      whereArgs: ['table'],
    );
    final tableNames = tableRows.map((row) => row['name'] as String).toSet();
    for (final table in requiredTablesFor(version)) {
      if (!tableNames.contains(table)) {
        throw StateError('SQLite schema is missing table "$table".');
      }
      await _validateColumns(db, table);
    }

    final indexRows = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: 'type = ?',
      whereArgs: ['index'],
    );
    final indexNames = indexRows.map((row) => row['name'] as String).toSet();
    for (final index in requiredIndexesFor(version)) {
      if (!indexNames.contains(index)) {
        throw StateError('SQLite schema is missing index "$index".');
      }
    }

    return version;
  }

  static Future<void> createSchema(
    sqflite.DatabaseExecutor db,
    int version,
  ) async {
    _checkSupportedVersion(version);

    await _createV1(db);
    if (version >= 2) {
      await _createV2(db);
    }
    if (version >= 3) {
      await _createV3(db);
    }
    if (version >= 4) {
      await _createV4(db);
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
        case 3:
          await _createV3(db);
          break;
        case 4:
          await _createV4(db);
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

  static Future<void> _createV3(sqflite.DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE maintenance_items (
        id TEXT PRIMARY KEY,
        vehicle_id TEXT NOT NULL,
        name TEXT NOT NULL,
        category TEXT,
        mileage_interval INTEGER CHECK (mileage_interval IS NULL OR mileage_interval > 0),
        time_interval_days INTEGER CHECK (time_interval_days IS NULL OR time_interval_days > 0),
        mileage_warning INTEGER NOT NULL DEFAULT 1000 CHECK (mileage_warning >= 0),
        date_warning_days INTEGER NOT NULL DEFAULT 30 CHECK (date_warning_days >= 0),
        reminder_enabled INTEGER NOT NULL DEFAULT 1 CHECK (reminder_enabled IN (0, 1)),
        is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (vehicle_id) REFERENCES vehicles (id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE services (
        id TEXT PRIMARY KEY,
        vehicle_id TEXT NOT NULL,
        event_datetime TEXT NOT NULL,
        odometer INTEGER CHECK (odometer IS NULL OR odometer >= 0),
        total_cost_minor INTEGER NOT NULL DEFAULT 0 CHECK (total_cost_minor >= 0),
        garage TEXT,
        notes TEXT,
        is_baseline INTEGER NOT NULL DEFAULT 0 CHECK (is_baseline IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (vehicle_id) REFERENCES vehicles (id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE service_items (
        id TEXT PRIMARY KEY,
        service_id TEXT NOT NULL,
        maintenance_item_id TEXT,
        item_name TEXT NOT NULL,
        allocated_cost_minor INTEGER CHECK (allocated_cost_minor IS NULL OR allocated_cost_minor >= 0),
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (service_id) REFERENCES services (id)
          ON UPDATE CASCADE
          ON DELETE CASCADE,
        FOREIGN KEY (maintenance_item_id) REFERENCES maintenance_items (id)
          ON UPDATE CASCADE
          ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_maintenance_items_vehicle_active
      ON maintenance_items (vehicle_id, is_archived, name COLLATE NOCASE)
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX idx_maintenance_items_active_name
      ON maintenance_items (vehicle_id, name COLLATE NOCASE)
      WHERE is_archived = 0
    ''');
    await db.execute('''
      CREATE INDEX idx_services_vehicle_event
      ON services (vehicle_id, event_datetime DESC)
    ''');
    await db.execute('''
      CREATE INDEX idx_services_vehicle_odometer
      ON services (vehicle_id, odometer)
    ''');
    await db.execute('''
      CREATE INDEX idx_service_items_service
      ON service_items (service_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_service_items_maintenance_item
      ON service_items (maintenance_item_id)
    ''');
  }

  static Future<void> _createV4(sqflite.DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE documents (
        id TEXT PRIMARY KEY,
        vehicle_id TEXT NOT NULL,
        category TEXT NOT NULL,
        title TEXT NOT NULL,
        issue_date TEXT,
        expiry_date TEXT,
        reference_number TEXT,
        provider TEXT,
        notes TEXT,
        reminder_id TEXT,
        is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
        archived_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (vehicle_id) REFERENCES vehicles (id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE attachments (
        id TEXT PRIMARY KEY,
        parent_type TEXT NOT NULL CHECK (parent_type IN ('DOCUMENT', 'REFUEL', 'SERVICE', 'EXPENSE', 'INCOME', 'VEHICLE')),
        parent_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        stored_path TEXT NOT NULL,
        mime_type TEXT,
        file_size INTEGER CHECK (file_size IS NULL OR file_size >= 0),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_documents_vehicle_active_expiry
      ON documents (vehicle_id, is_archived, expiry_date)
    ''');
    await db.execute('''
      CREATE INDEX idx_documents_vehicle_category
      ON documents (vehicle_id, category COLLATE NOCASE)
    ''');
    await db.execute('''
      CREATE INDEX idx_attachments_parent
      ON attachments (parent_type, parent_id)
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX idx_attachments_stored_path
      ON attachments (stored_path)
    ''');
  }

  static Future<void> _validateColumns(
    sqflite.DatabaseExecutor db,
    String table,
  ) async {
    final expectedColumns = _requiredColumnsByTable[table];
    if (expectedColumns == null) {
      throw StateError('No schema column contract registered for "$table".');
    }
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final actualColumns = info.map((row) => row['name'] as String).toSet();
    for (final column in expectedColumns) {
      if (!actualColumns.contains(column)) {
        throw StateError(
          'SQLite schema table "$table" is missing column "$column".',
        );
      }
    }
  }

  static void _checkSupportedVersion(int version) {
    if (version < 1 || version > schemaVersion) {
      throw StateError('Unsupported schema version $version.');
    }
  }
}
