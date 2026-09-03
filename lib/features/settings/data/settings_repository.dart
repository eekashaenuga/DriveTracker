import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/database/app_database.dart';

class SettingsRepository {
  SettingsRepository(this._database);

  static const selectedVehicleIdKey = 'selected_vehicle_id';
  static const themeModeKey = 'theme_mode';

  final AppDatabase _database;

  Future<String?> getSelectedVehicleId({sqflite.DatabaseExecutor? executor}) {
    return getString(selectedVehicleIdKey, executor: executor);
  }

  Future<void> setSelectedVehicleId(
    String? vehicleId, {
    sqflite.DatabaseExecutor? executor,
  }) {
    return setString(selectedVehicleIdKey, vehicleId, executor: executor);
  }

  Future<String?> getThemeMode({sqflite.DatabaseExecutor? executor}) {
    return getString(themeModeKey, executor: executor);
  }

  Future<void> setThemeMode(
    String value, {
    sqflite.DatabaseExecutor? executor,
  }) {
    return setString(themeModeKey, value, executor: executor);
  }

  Future<String?> getString(
    String key, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['value'] as String;
  }

  Future<void> setString(
    String key,
    String? value, {
    sqflite.DatabaseExecutor? executor,
  }) async {
    final db = await _executor(executor);
    if (value == null) {
      await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
      return;
    }

    await db.insert('app_settings', {
      'key': key,
      'value': value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
  }

  Future<sqflite.DatabaseExecutor> _executor(
    sqflite.DatabaseExecutor? executor,
  ) async {
    return executor ?? await _database.database;
  }
}
