import 'package:flutter/material.dart';

import '../../features/daily_records/domain/expense.dart';
import '../../features/daily_records/domain/income.dart';
import '../../features/daily_records/domain/refuel.dart';
import '../../features/daily_records/presentation/expense_form_screen.dart';
import '../../features/daily_records/presentation/history_screen.dart';
import '../../features/daily_records/presentation/income_form_screen.dart';
import '../../features/daily_records/presentation/refuel_form_screen.dart';
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

  static Future<void> openRefuel(BuildContext context, {Refuel? refuel}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RefuelFormScreen(refuel: refuel)),
    );
  }

  static Future<void> openExpense(BuildContext context, {Expense? expense}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExpenseFormScreen(expense: expense),
      ),
    );
  }

  static Future<void> openIncome(BuildContext context, {Income? income}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => IncomeFormScreen(income: income)),
    );
  }

  static Future<void> openHistory(BuildContext context) {
    return Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const HistoryScreen()));
  }

  static Future<void> openSettings(BuildContext context) {
    return Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }
}
