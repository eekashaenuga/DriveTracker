import '../../../core/utilities/validation_exception.dart';
import '../../odometer/data/odometer_repository.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../domain/vehicle_dashboard.dart';

class HomeRepository {
  HomeRepository({
    required this.vehicleRepository,
    required this.odometerRepository,
  });

  final VehicleRepository vehicleRepository;
  final OdometerRepository odometerRepository;

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

    return VehicleDashboard(
      vehicle: vehicle,
      currentOdometer: currentOdometer,
      recentOdometerEntries: recentOdometerEntries,
    );
  }
}
