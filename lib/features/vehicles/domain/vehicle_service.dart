import '../../../core/database/app_database.dart';
import '../../../core/utilities/id_generator.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../odometer/data/odometer_repository.dart';
import '../../odometer/domain/odometer_entry.dart';
import '../../settings/data/settings_repository.dart';
import '../data/vehicle_repository.dart';
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
      purchaseMileage: draft.purchaseMileage,
      purchasePrice: draft.purchasePrice,
      seller: VehicleValidator.cleanOptional(draft.seller),
      notes: VehicleValidator.cleanOptional(draft.notes),
      isArchived: existing.isArchived,
      createdAt: existing.createdAt,
      updatedAt: _clock().toUtc(),
    );

    await vehicleRepository.update(updated);
    return updated;
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
}
