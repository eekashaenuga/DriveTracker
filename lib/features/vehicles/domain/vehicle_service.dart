import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/database/app_database.dart';
import '../../../core/utilities/id_generator.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../odometer/data/odometer_repository.dart';
import '../../odometer/domain/odometer_entry.dart';
import '../../settings/data/settings_repository.dart';
import '../data/vehicle_repository.dart';
import 'distance_unit_conversion.dart';
import 'vehicle.dart';
import 'vehicle_draft.dart';
import 'vehicle_validator.dart';

typedef Clock = DateTime Function();

class VehicleService {
  VehicleService({
    required this.database,
    required this.vehicleRepository,
    required this.odometerRepository,
    required this.settingsRepository,
    IdGenerator? idGenerator,
    Clock? clock,
  }) : _idGenerator = idGenerator ?? IdGenerator(),
       _clock = clock ?? (() => DateTime.now().toUtc());

  final AppDatabase database;
  final VehicleRepository vehicleRepository;
  final OdometerRepository odometerRepository;
  final SettingsRepository settingsRepository;
  final IdGenerator _idGenerator;
  final Clock _clock;

  Future<Vehicle> addVehicle(VehicleDraft draft) async {
    VehicleValidator.throwIfInvalid(draft, requireInitialOdometer: true);

    final now = _clock().toUtc();
    final vehicle = Vehicle(
      id: _idGenerator.newId('veh'),
      name: VehicleValidator.cleanRequired(draft.name),
      make: VehicleValidator.cleanRequired(draft.make),
      model: VehicleValidator.cleanRequired(draft.model),
      year: draft.year,
      registration: VehicleValidator.cleanOptional(draft.registration),
      fuelType: draft.fuelType,
      distanceUnit: draft.distanceUnit,
      photoPath: VehicleValidator.cleanOptional(draft.photoPath),
      trim: VehicleValidator.cleanOptional(draft.trim),
      engine: VehicleValidator.cleanOptional(draft.engine),
      transmission: VehicleValidator.cleanOptional(draft.transmission),
      vin: VehicleValidator.cleanOptional(draft.vin),
      colour: VehicleValidator.cleanOptional(draft.colour),
      purchaseDate: draft.purchaseDate,
      purchaseMileage: draft.purchaseMileage,
      purchasePrice: draft.purchasePrice,
      seller: VehicleValidator.cleanOptional(draft.seller),
      notes: VehicleValidator.cleanOptional(draft.notes),
      isArchived: false,
      createdAt: now,
      updatedAt: now,
    );
    final initialEntry = OdometerEntry(
      id: _idGenerator.newId('odo'),
      vehicleId: vehicle.id,
      odometer: draft.currentOdometer!,
      eventDateTime: now,
      sourceType: OdometerSourceType.manual,
      createdAt: now,
      updatedAt: now,
    );

    await database.transaction((txn) async {
      await vehicleRepository.insert(vehicle, executor: txn);
      await odometerRepository.insert(initialEntry, executor: txn);
      await settingsRepository.setSelectedVehicleId(vehicle.id, executor: txn);
    });

    return vehicle;
  }

  Future<Vehicle> updateVehicle(String vehicleId, VehicleDraft draft) async {
    VehicleValidator.throwIfInvalid(draft, requireInitialOdometer: false);
    final existing = await vehicleRepository.getById(vehicleId);
    if (existing == null) {
      throw const ValidationException(['Vehicle not found.']);
    }

    final now = _clock().toUtc();
    final distanceUnitChanged = existing.distanceUnit != draft.distanceUnit;
    final purchaseMileage =
        distanceUnitChanged &&
            draft.purchaseMileage != null &&
            draft.purchaseMileage == existing.purchaseMileage
        ? DistanceUnitConversion.convertWholeDistance(
            draft.purchaseMileage!,
            from: existing.distanceUnit,
            to: draft.distanceUnit,
          )
        : draft.purchaseMileage;

    final updated = Vehicle(
      id: existing.id,
      name: VehicleValidator.cleanRequired(draft.name),
      make: VehicleValidator.cleanRequired(draft.make),
      model: VehicleValidator.cleanRequired(draft.model),
      year: draft.year,
      registration: VehicleValidator.cleanOptional(draft.registration),
      fuelType: draft.fuelType,
      distanceUnit: draft.distanceUnit,
      photoPath: VehicleValidator.cleanOptional(draft.photoPath),
      trim: VehicleValidator.cleanOptional(draft.trim),
      engine: VehicleValidator.cleanOptional(draft.engine),
      transmission: VehicleValidator.cleanOptional(draft.transmission),
      vin: VehicleValidator.cleanOptional(draft.vin),
      colour: VehicleValidator.cleanOptional(draft.colour),
      purchaseDate: draft.purchaseDate,
      purchaseMileage: purchaseMileage,
      purchasePrice: draft.purchasePrice,
      seller: VehicleValidator.cleanOptional(draft.seller),
      notes: VehicleValidator.cleanOptional(draft.notes),
      isArchived: existing.isArchived,
      createdAt: existing.createdAt,
      updatedAt: now,
    );

    await database.transaction((txn) async {
      if (distanceUnitChanged) {
        await _convertVehicleDistanceValues(
          txn,
          vehicleId: vehicleId,
          from: existing.distanceUnit,
          to: draft.distanceUnit,
          updatedAt: now,
          includeVehicleProfileDistances: false,
        );
      }
      await vehicleRepository.update(updated, executor: txn);
    });
    return updated;
  }

  Future<Vehicle> updateVehicleDistanceUnit(
    String vehicleId,
    DistanceUnit distanceUnit,
  ) async {
    final existing = await vehicleRepository.getById(vehicleId);
    if (existing == null) {
      throw const ValidationException(['Vehicle not found.']);
    }
    if (existing.distanceUnit == distanceUnit) {
      return existing;
    }

    final now = _clock().toUtc();

    await database.transaction((txn) async {
      await _convertVehicleDistanceValues(
        txn,
        vehicleId: vehicleId,
        from: existing.distanceUnit,
        to: distanceUnit,
        updatedAt: now,
        includeVehicleProfileDistances: true,
      );
      await txn.update(
        'vehicles',
        {
          'distance_unit': distanceUnit.storageValue,
          'updated_at': now.toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [vehicleId],
      );
    });

    final updated = await vehicleRepository.getById(vehicleId);
    return updated ?? (throw const ValidationException(['Vehicle not found.']));
  }

  Future<void> archiveVehicle(String vehicleId) async {
    final now = _clock().toUtc();

    await database.transaction((txn) async {
      final vehicle = await vehicleRepository.getById(vehicleId, executor: txn);
      if (vehicle == null) {
        throw const ValidationException(['Vehicle not found.']);
      }
      if (vehicle.isArchived) {
        return;
      }

      await vehicleRepository.archive(vehicleId, now, executor: txn);

      final selectedVehicleId = await settingsRepository.getSelectedVehicleId(
        executor: txn,
      );
      if (selectedVehicleId != vehicleId) {
        return;
      }

      final activeVehicles = await vehicleRepository.listActive(executor: txn);
      await settingsRepository.setSelectedVehicleId(
        activeVehicles.isEmpty ? null : activeVehicles.first.id,
        executor: txn,
      );
    });
  }

  Future<void> restoreVehicle(String vehicleId) async {
    final now = _clock().toUtc();

    await database.transaction((txn) async {
      final vehicle = await vehicleRepository.getById(vehicleId, executor: txn);
      if (vehicle == null) {
        throw const ValidationException(['Vehicle not found.']);
      }
      if (!vehicle.isArchived) {
        return;
      }

      await vehicleRepository.restore(vehicleId, now, executor: txn);

      final selectedVehicleId = await settingsRepository.getSelectedVehicleId(
        executor: txn,
      );
      if (selectedVehicleId == null) {
        await settingsRepository.setSelectedVehicleId(vehicleId, executor: txn);
      }
    });
  }

  Future<void> _convertVehicleDistanceValues(
    sqflite.DatabaseExecutor executor, {
    required String vehicleId,
    required DistanceUnit from,
    required DistanceUnit to,
    required DateTime updatedAt,
    required bool includeVehicleProfileDistances,
  }) async {
    final factor = DistanceUnitConversion.factor(from: from, to: to);
    final timestamp = updatedAt.toUtc().toIso8601String();

    if (includeVehicleProfileDistances) {
      await executor.rawUpdate(
        '''
        UPDATE vehicles
        SET purchase_mileage = CASE
              WHEN purchase_mileage IS NULL THEN NULL
              ELSE CAST(ROUND(purchase_mileage * ?) AS INTEGER)
            END,
            updated_at = ?
        WHERE id = ?
        ''',
        [factor, timestamp, vehicleId],
      );
    }

    await executor.rawUpdate(
      '''
      UPDATE odometer_entries
      SET odometer = CAST(ROUND(odometer * ?) AS INTEGER),
          updated_at = ?
      WHERE vehicle_id = ?
      ''',
      [factor, timestamp, vehicleId],
    );
    await executor.rawUpdate(
      '''
      UPDATE refuels
      SET odometer = CAST(ROUND(odometer * ?) AS INTEGER),
          updated_at = ?
      WHERE vehicle_id = ?
      ''',
      [factor, timestamp, vehicleId],
    );
    await _convertNullableDistanceColumn(
      executor,
      table: 'expenses',
      column: 'odometer',
      vehicleId: vehicleId,
      factor: factor,
      timestamp: timestamp,
    );
    await _convertNullableDistanceColumn(
      executor,
      table: 'income_records',
      column: 'odometer',
      vehicleId: vehicleId,
      factor: factor,
      timestamp: timestamp,
    );
    await _convertNullableDistanceColumn(
      executor,
      table: 'services',
      column: 'odometer',
      vehicleId: vehicleId,
      factor: factor,
      timestamp: timestamp,
    );
    await executor.rawUpdate(
      '''
      UPDATE maintenance_items
      SET mileage_interval = CASE
            WHEN mileage_interval IS NULL THEN NULL
            ELSE CAST(ROUND(mileage_interval * ?) AS INTEGER)
          END,
          mileage_warning = CAST(ROUND(mileage_warning * ?) AS INTEGER),
          updated_at = ?
      WHERE vehicle_id = ?
      ''',
      [factor, factor, timestamp, vehicleId],
    );
  }

  Future<void> _convertNullableDistanceColumn(
    sqflite.DatabaseExecutor executor, {
    required String table,
    required String column,
    required String vehicleId,
    required double factor,
    required String timestamp,
  }) {
    return executor.rawUpdate(
      '''
      UPDATE $table
      SET $column = CASE
            WHEN $column IS NULL THEN NULL
            ELSE CAST(ROUND($column * ?) AS INTEGER)
          END,
          updated_at = ?
      WHERE vehicle_id = ?
      ''',
      [factor, timestamp, vehicleId],
    );
  }
}
