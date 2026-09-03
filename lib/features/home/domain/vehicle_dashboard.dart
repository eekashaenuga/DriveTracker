import '../../odometer/domain/odometer_entry.dart';
import '../../vehicles/domain/vehicle.dart';

class VehicleDashboard {
  const VehicleDashboard({
    required this.vehicle,
    required this.currentOdometer,
    required this.recentOdometerEntries,
  });

  final Vehicle vehicle;
  final int? currentOdometer;
  final List<OdometerEntry> recentOdometerEntries;
}
