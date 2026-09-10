import 'package:flutter/material.dart';

import '../../features/calculator/presentation/fuel_calculator_screen.dart';
import '../../features/daily_records/domain/expense.dart';
import '../../features/daily_records/domain/history_filter.dart';
import '../../features/daily_records/domain/income.dart';
import '../../features/daily_records/domain/refuel.dart';
import '../../features/daily_records/presentation/expense_form_screen.dart';
import '../../features/daily_records/presentation/history_screen.dart';
import '../../features/daily_records/presentation/income_form_screen.dart';
import '../../features/daily_records/presentation/refuel_form_screen.dart';
import '../../features/documents/domain/vehicle_document.dart';
import '../../features/documents/presentation/document_details_screen.dart';
import '../../features/documents/presentation/document_form_screen.dart';
import '../../features/documents/presentation/documents_screen.dart';
import '../../features/maintenance/domain/maintenance_item.dart';
import '../../features/maintenance/domain/service_record.dart';
import '../../features/maintenance/presentation/maintenance_item_details_screen.dart';
import '../../features/maintenance/presentation/maintenance_item_form_screen.dart';
import '../../features/maintenance/presentation/maintenance_screen.dart';
import '../../features/maintenance/presentation/service_form_screen.dart';
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

  static Future<void> openService(
    BuildContext context, {
    ServiceRecordWithItems? service,
    String? preselectedMaintenanceItemId,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServiceFormScreen(
          service: service,
          preselectedMaintenanceItemId: preselectedMaintenanceItemId,
        ),
      ),
    );
  }

  static Future<void> openMaintenance(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const MaintenanceScreen()));
  }

  static Future<void> openDocuments(BuildContext context) {
    return Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const DocumentsScreen()));
  }

  static Future<VehicleDocument?> openAddDocument(BuildContext context) {
    return Navigator.of(context).push<VehicleDocument>(
      MaterialPageRoute<VehicleDocument>(
        builder: (_) => const DocumentFormScreen(),
      ),
    );
  }

  static Future<VehicleDocument?> openEditDocument(
    BuildContext context,
    VehicleDocument document,
  ) {
    return Navigator.of(context).push<VehicleDocument>(
      MaterialPageRoute<VehicleDocument>(
        builder: (_) => DocumentFormScreen(document: document),
      ),
    );
  }

  static Future<VehicleDocument?> openRenewDocument(
    BuildContext context,
    VehicleDocument document,
  ) {
    return Navigator.of(context).push<VehicleDocument>(
      MaterialPageRoute<VehicleDocument>(
        builder: (_) => DocumentFormScreen(renewingFrom: document),
      ),
    );
  }

  static Future<void> openDocumentDetails(
    BuildContext context,
    String documentId,
  ) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentDetailsScreen(documentId: documentId),
      ),
    );
  }

  static Future<void> openAddMaintenanceItem(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const MaintenanceItemFormScreen(),
      ),
    );
  }

  static Future<void> openEditMaintenanceItem(
    BuildContext context,
    MaintenanceItem item,
  ) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MaintenanceItemFormScreen(item: item),
      ),
    );
  }

  static Future<void> openMaintenanceItemDetails(
    BuildContext context,
    String itemId,
  ) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MaintenanceItemDetailsScreen(itemId: itemId),
      ),
    );
  }

  static Future<void> openHistory(
    BuildContext context, {
    HistoryFilter? filter,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryScreen(initialFilter: filter),
      ),
    );
  }

  static Future<void> openSettings(BuildContext context) {
    return Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  static Future<void> openFuelCalculator(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const FuelCalculatorScreen()),
    );
  }
}
