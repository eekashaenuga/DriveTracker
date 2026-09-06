import '../../../core/utilities/validation_exception.dart';
import '../../daily_records/data/activity_repository.dart';
import '../../daily_records/data/financial_summary_repository.dart';
import '../../daily_records/data/refuel_repository.dart';
import '../../daily_records/domain/fuel_economy_calculator.dart';
import '../../maintenance/data/maintenance_item_repository.dart';
import '../../maintenance/data/service_record_repository.dart';
import '../../maintenance/domain/maintenance_reminder.dart';
import '../../maintenance/domain/maintenance_reminder_engine.dart';
import '../../odometer/data/odometer_repository.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../domain/vehicle_dashboard.dart';

class HomeRepository {
  HomeRepository({
    required this.vehicleRepository,
    required this.odometerRepository,
    required this.refuelRepository,
    required this.financialSummaryRepository,
    required this.activityRepository,
    required this.maintenanceItemRepository,
    required this.serviceRecordRepository,
    MaintenanceReminderEngine? reminderEngine,
  }) : _reminderEngine = reminderEngine ?? const MaintenanceReminderEngine();

  final VehicleRepository vehicleRepository;
  final OdometerRepository odometerRepository;
  final RefuelRepository refuelRepository;
  final FinancialSummaryRepository financialSummaryRepository;
  final ActivityRepository activityRepository;
  final MaintenanceItemRepository maintenanceItemRepository;
  final ServiceRecordRepository serviceRecordRepository;
  final MaintenanceReminderEngine _reminderEngine;

  Future<VehicleDashboard> getVehicleDashboard(String vehicleId) async {
    final vehicle = await vehicleRepository.getById(vehicleId);
    if (vehicle == null) {
      throw const ValidationException(['Vehicle not found.']);
    }

    final currentOdometer = await odometerRepository.currentOdometerForVehicle(
      vehicleId,
    );
    final recentOdometerEntries = await odometerRepository.recentForVehicle(
      vehicleId,
      limit: 6,
    );
    final monthSpendMinor = await financialSummaryRepository
        .monthSpendForVehicle(vehicleId);
    final latestRefuel = await financialSummaryRepository
        .latestRefuelForVehicle(vehicleId);
    final refuels = await refuelRepository.listForVehicle(
      vehicleId,
      ascending: true,
    );
    final latestFuelEconomyInterval = FuelEconomyCalculator.latestValidInterval(
      refuels: refuels,
      distanceUnit: vehicle.distanceUnit,
    );
    final recentActivity = await activityRepository.listForVehicle(
      vehicleId,
      limit: 6,
    );
    final maintenanceItems = await maintenanceItemRepository.listForVehicle(
      vehicleId,
    );
    final reminders = <MaintenanceReminder>[];
    for (final item in maintenanceItems) {
      final completions = await serviceRecordRepository
          .completionsForMaintenanceItem(vehicleId, item.id);
      reminders.add(
        _reminderEngine.evaluate(
          item: item,
          completions: completions,
          currentOdometer: currentOdometer,
          asOf: DateTime.now(),
        ),
      );
    }
    final nextMaintenanceAttention = _reminderEngine.mostUrgent(reminders);

    return VehicleDashboard(
      vehicle: vehicle,
      currentOdometer: currentOdometer,
      recentOdometerEntries: recentOdometerEntries,
      monthSpendMinor: monthSpendMinor,
      latestFuelPriceMicrosPerLitre: latestRefuel?.unitPriceMicrosPerLitre,
      latestFuelEconomyInterval: latestFuelEconomyInterval,
      recentActivity: recentActivity,
      nextMaintenanceAttention: nextMaintenanceAttention,
    );
  }
}
