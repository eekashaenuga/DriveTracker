import 'package:flutter/material.dart';

import '../core/database/app_database.dart';
import '../core/utilities/validation_exception.dart';
import '../features/home/data/home_repository.dart';
import '../features/home/domain/vehicle_dashboard.dart';
import '../features/odometer/data/odometer_repository.dart';
import '../features/odometer/domain/odometer_entry.dart';
import '../features/odometer/domain/odometer_policy.dart';
import '../features/odometer/domain/odometer_service.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/vehicles/data/vehicle_repository.dart';
import '../features/vehicles/domain/vehicle.dart';
import '../features/vehicles/domain/vehicle_draft.dart';
import '../features/vehicles/domain/vehicle_service.dart';

class DriveTrackerController extends ChangeNotifier {
  DriveTrackerController({required AppDatabase database})
    : _database = database,
      _vehicleRepository = VehicleRepository(database),
      _odometerRepository = OdometerRepository(database),
      _settingsRepository = SettingsRepository(database) {
    _homeRepository = HomeRepository(
      vehicleRepository: _vehicleRepository,
      odometerRepository: _odometerRepository,
    );
    _vehicleService = VehicleService(
      database: _database,
      vehicleRepository: _vehicleRepository,
      odometerRepository: _odometerRepository,
      settingsRepository: _settingsRepository,
    );
    _odometerService = OdometerService(
      vehicleRepository: _vehicleRepository,
      odometerRepository: _odometerRepository,
    );
  }

  static const _themeSystem = 'system';
  static const _themeLight = 'light';
  static const _themeDark = 'dark';

  final AppDatabase _database;
  final VehicleRepository _vehicleRepository;
  final OdometerRepository _odometerRepository;
  final SettingsRepository _settingsRepository;
  late final HomeRepository _homeRepository;
  late final VehicleService _vehicleService;
  late final OdometerService _odometerService;

  bool _initialized = false;
  bool _busy = false;
  String? _errorMessage;
  ThemeMode _themeMode = ThemeMode.system;
  List<Vehicle> _activeVehicles = const [];
  List<Vehicle> _archivedVehicles = const [];
  VehicleDashboard? _dashboard;

  bool get initialized => _initialized;
  bool get isBusy => _busy;
  String? get errorMessage => _errorMessage;
  ThemeMode get themeMode => _themeMode;
  List<Vehicle> get activeVehicles => List.unmodifiable(_activeVehicles);
  List<Vehicle> get archivedVehicles => List.unmodifiable(_archivedVehicles);
  bool get hasAnyVehicles =>
      _activeVehicles.isNotEmpty || _archivedVehicles.isNotEmpty;
  bool get hasActiveVehicles => _activeVehicles.isNotEmpty;
  Vehicle? get selectedVehicle => _dashboard?.vehicle;
  int? get currentOdometer => _dashboard?.currentOdometer;
  List<OdometerEntry> get recentOdometerEntries {
    return List.unmodifiable(_dashboard?.recentOdometerEntries ?? const []);
  }

  Future<int?> currentOdometerForVehicle(String vehicleId) {
    return _odometerRepository.currentOdometerForVehicle(vehicleId);
  }

  Future<List<OdometerEntry>> odometerEntriesForVehicle(String vehicleId) {
    return _odometerRepository.recentForVehicle(vehicleId, limit: 20);
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _busy = true;
    notifyListeners();

    try {
      _themeMode = _themeModeFromStorage(
        await _settingsRepository.getThemeMode(),
      );
      await _reloadData();
      _errorMessage = null;
    } catch (_) {
      _errorMessage = 'DriveTracker could not load your local data.';
    } finally {
      _initialized = true;
      _busy = false;
      notifyListeners();
    }
  }

  Future<Vehicle> addVehicle(VehicleDraft draft) async {
    return _runMutation(() async {
      final vehicle = await _vehicleService.addVehicle(draft);
      await _reloadData(preferredVehicleId: vehicle.id);
      return vehicle;
    });
  }

  Future<Vehicle> updateVehicle(String vehicleId, VehicleDraft draft) async {
    return _runMutation(() async {
      final vehicle = await _vehicleService.updateVehicle(vehicleId, draft);
      await _reloadData(preferredVehicleId: vehicle.id);
      return vehicle;
    });
  }

  Future<void> archiveVehicle(String vehicleId) async {
    return _runMutation(() async {
      await _vehicleService.archiveVehicle(vehicleId);
      await _reloadData();
    });
  }

  Future<void> selectVehicle(String vehicleId) async {
    return _runMutation(() async {
      final canSelect = _activeVehicles.any(
        (vehicle) => vehicle.id == vehicleId,
      );
      if (!canSelect) {
        throw const ValidationException(['Vehicle is not available.']);
      }
      await _settingsRepository.setSelectedVehicleId(vehicleId);
      await _reloadData(preferredVehicleId: vehicleId);
    });
  }

  OdometerAssessment assessOdometerUpdate(int reading) {
    return _odometerService.assessManualReading(
      currentOdometer: currentOdometer,
      newOdometer: reading,
    );
  }

  Future<OdometerEntry> updateOdometer(
    int reading, {
    bool allowHistorical = false,
    bool confirmLargeIncrease = false,
  }) async {
    final vehicle = selectedVehicle;
    if (vehicle == null) {
      throw const ValidationException([
        'Select a vehicle before updating mileage.',
      ]);
    }

    return _runMutation(() async {
      final entry = await _odometerService.recordManualReading(
        vehicleId: vehicle.id,
        odometer: reading,
        allowHistorical: allowHistorical,
        confirmLargeIncrease: confirmLargeIncrease,
      );
      await _reloadData(preferredVehicleId: vehicle.id);
      return entry;
    });
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    return _runMutation(() async {
      _themeMode = mode;
      await _settingsRepository.setThemeMode(_themeModeToStorage(mode));
    });
  }

  Future<T> _runMutation<T>(Future<T> Function() action) async {
    _busy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      return await action();
    } on ValidationException catch (error) {
      _errorMessage = error.message;
      rethrow;
    } catch (_) {
      _errorMessage = 'Something went wrong. Please try again.';
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _reloadData({String? preferredVehicleId}) async {
    _activeVehicles = await _vehicleRepository.listActive();
    _archivedVehicles = await _vehicleRepository.listArchived();

    final selectedId =
        preferredVehicleId ?? await _settingsRepository.getSelectedVehicleId();
    final selected =
        _findActiveVehicle(selectedId) ??
        (_activeVehicles.isEmpty ? null : _activeVehicles.first);

    if (selected == null) {
      await _settingsRepository.setSelectedVehicleId(null);
      _dashboard = null;
      return;
    }

    if (selected.id != selectedId) {
      await _settingsRepository.setSelectedVehicleId(selected.id);
    }
    _dashboard = await _homeRepository.getVehicleDashboard(selected.id);
  }

  Vehicle? _findActiveVehicle(String? vehicleId) {
    if (vehicleId == null) {
      return null;
    }
    for (final vehicle in _activeVehicles) {
      if (vehicle.id == vehicleId) {
        return vehicle;
      }
    }
    return null;
  }

  ThemeMode _themeModeFromStorage(String? value) {
    switch (value) {
      case _themeLight:
        return ThemeMode.light;
      case _themeDark:
        return ThemeMode.dark;
      case _themeSystem:
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeToStorage(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return _themeLight;
      case ThemeMode.dark:
        return _themeDark;
      case ThemeMode.system:
        return _themeSystem;
    }
  }
}
