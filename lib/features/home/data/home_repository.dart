import '../../../core/utilities/validation_exception.dart';
import '../../daily_records/data/activity_repository.dart';
import '../../daily_records/data/financial_summary_repository.dart';
import '../../daily_records/data/refuel_repository.dart';
import '../../daily_records/domain/fuel_economy_calculator.dart';
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
  });

  final VehicleRepository vehicleRepository;
  final OdometerRepository odometerRepository;
  final RefuelRepository refuelRepository;
  final FinancialSummaryRepository financialSummaryRepository;
  final ActivityRepository activityRepository;

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

    return VehicleDashboard(
      vehicle: vehicle,
      currentOdometer: currentOdometer,
      recentOdometerEntries: recentOdometerEntries,
      monthSpendMinor: monthSpendMinor,
      latestFuelPriceMicrosPerLitre: latestRefuel?.unitPriceMicrosPerLitre,
      latestFuelEconomyInterval: latestFuelEconomyInterval,
      recentActivity: recentActivity,
    );
  }
}
