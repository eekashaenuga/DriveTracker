import 'package:flutter/material.dart';

import '../../features/calculator/presentation/fuel_calculator_screen.dart';
import '../../features/data_safety/presentation/data_storage_screen.dart';
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
import '../../features/odometer/domain/odometer_entry.dart';
import '../../features/odometer/presentation/odometer_entry_form_screen.dart';
import '../../features/odometer/presentation/update_odometer_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/vehicle_units_screen.dart';
import '../../features/vehicles/domain/vehicle.dart';
import '../../features/vehicles/presentation/vehicle_details_screen.dart';
import '../../features/vehicles/presentation/vehicle_form_screen.dart';
import '../../features/vehicles/presentation/vehicles_screen.dart';
import '../theme/dt_motion.dart';

class AppNavigation {
  const AppNavigation._();

  static Future<void> openAddVehicle(
    BuildContext context, {
    bool firstVehicle = false,
  }) {
    return _push<void>(
      context,
      (_) => VehicleFormScreen(firstVehicle: firstVehicle),
    );
  }

  static Future<void> openEditVehicle(BuildContext context, Vehicle vehicle) {
    return _push<void>(context, (_) => VehicleFormScreen(vehicle: vehicle));
  }

  static Future<void> openVehicleDetails(
    BuildContext context,
    Vehicle vehicle,
  ) {
    return _push<void>(
      context,
      (_) => VehicleDetailsScreen(vehicleId: vehicle.id),
    );
  }

  static Future<void> openVehicles(BuildContext context) {
    return _push<void>(context, (_) => const VehiclesScreen());
  }

  static Future<void> openUpdateOdometer(BuildContext context) {
    return _push<void>(context, (_) => const UpdateOdometerScreen());
  }

  static Future<void> openEditOdometerEntry(
    BuildContext context,
    OdometerEntry entry,
  ) {
    return _push<void>(context, (_) => OdometerEntryFormScreen(entry: entry));
  }

  static Future<void> openRefuel(BuildContext context, {Refuel? refuel}) {
    return _push<void>(context, (_) => RefuelFormScreen(refuel: refuel));
  }

  static Future<void> openExpense(BuildContext context, {Expense? expense}) {
    return _push<void>(context, (_) => ExpenseFormScreen(expense: expense));
  }

  static Future<void> openIncome(BuildContext context, {Income? income}) {
    return _push<void>(context, (_) => IncomeFormScreen(income: income));
  }

  static Future<void> openService(
    BuildContext context, {
    ServiceRecordWithItems? service,
    String? preselectedMaintenanceItemId,
  }) {
    return _push<void>(
      context,
      (_) => ServiceFormScreen(
        service: service,
        preselectedMaintenanceItemId: preselectedMaintenanceItemId,
      ),
    );
  }

  static Future<void> openMaintenance(BuildContext context) {
    return _push<void>(context, (_) => const MaintenanceScreen());
  }

  static Future<void> openDocuments(BuildContext context) {
    return _push<void>(context, (_) => const DocumentsScreen());
  }

  static Future<VehicleDocument?> openAddDocument(BuildContext context) {
    return _push<VehicleDocument>(context, (_) => const DocumentFormScreen());
  }

  static Future<VehicleDocument?> openEditDocument(
    BuildContext context,
    VehicleDocument document,
  ) {
    return _push<VehicleDocument>(
      context,
      (_) => DocumentFormScreen(document: document),
    );
  }

  static Future<VehicleDocument?> openRenewDocument(
    BuildContext context,
    VehicleDocument document,
  ) {
    return _push<VehicleDocument>(
      context,
      (_) => DocumentFormScreen(renewingFrom: document),
    );
  }

  static Future<void> openDocumentDetails(
    BuildContext context,
    String documentId,
  ) {
    return _push<void>(
      context,
      (_) => DocumentDetailsScreen(documentId: documentId),
    );
  }

  static Future<void> openAddMaintenanceItem(BuildContext context) {
    return _push<void>(context, (_) => const MaintenanceItemFormScreen());
  }

  static Future<void> openEditMaintenanceItem(
    BuildContext context,
    MaintenanceItem item,
  ) {
    return _push<void>(context, (_) => MaintenanceItemFormScreen(item: item));
  }

  static Future<void> openMaintenanceItemDetails(
    BuildContext context,
    String itemId,
  ) {
    return _push<void>(
      context,
      (_) => MaintenanceItemDetailsScreen(itemId: itemId),
    );
  }

  static Future<void> openHistory(
    BuildContext context, {
    HistoryFilter? filter,
  }) {
    return _push<void>(context, (_) => HistoryScreen(initialFilter: filter));
  }

  static Future<void> openSettings(BuildContext context) {
    return _push<void>(context, (_) => const SettingsScreen());
  }

  static Future<void> openVehicleUnits(BuildContext context) {
    return _push<void>(context, (_) => const VehicleUnitsScreen());
  }

  static Future<void> openDataStorage(BuildContext context) {
    return _push<void>(context, (_) => const DataStorageScreen());
  }

  static Future<void> openFuelCalculator(BuildContext context) {
    return _push<void>(context, (_) => const FuelCalculatorScreen());
  }

  static Future<T?> _push<T>(BuildContext context, WidgetBuilder builder) {
    return Navigator.of(context).push(_route<T>(builder));
  }

  static PageRoute<T> _route<T>(WidgetBuilder builder) {
    return _DTMaterialPageRoute<T>(builder: builder);
  }
}

class _DTMaterialPageRoute<T> extends MaterialPageRoute<T> {
  _DTMaterialPageRoute({required super.builder});

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (DTMotion.reduceMotionOf(context)) {
      return child;
    }
    return super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}
