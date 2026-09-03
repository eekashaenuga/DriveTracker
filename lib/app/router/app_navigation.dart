import 'package:flutter/material.dart';

import '../../features/odometer/presentation/update_odometer_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/vehicles/domain/vehicle.dart';
import '../../features/vehicles/presentation/vehicle_details_screen.dart';
import '../../features/vehicles/presentation/vehicle_form_screen.dart';
import '../../features/vehicles/presentation/vehicles_screen.dart';

class AppNavigation {
  const AppNavigation._();

  static Future<void> openAddVehicle(
    BuildContext context, {
    bool firstVehicle = false,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VehicleFormScreen(firstVehicle: firstVehicle),
      ),
    );
  }

  static Future<void> openEditVehicle(BuildContext context, Vehicle vehicle) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VehicleFormScreen(vehicle: vehicle),
      ),
    );
  }

  static Future<void> openVehicleDetails(
    BuildContext context,
    Vehicle vehicle,
  ) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VehicleDetailsScreen(vehicleId: vehicle.id),
      ),
    );
  }

  static Future<void> openVehicles(BuildContext context) {
    return Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const VehiclesScreen()));
  }

  static Future<void> openUpdateOdometer(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const UpdateOdometerScreen()),
    );
  }

  static Future<void> openSettings(BuildContext context) {
    return Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }
}
