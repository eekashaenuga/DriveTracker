import '../../daily_records/domain/daily_activity.dart';
import '../../daily_records/domain/fuel_economy_calculator.dart';
import '../../daily_records/domain/monthly_spending.dart';
import '../../maintenance/domain/maintenance_reminder.dart';
import '../../odometer/domain/odometer_entry.dart';
import '../../vehicles/domain/vehicle.dart';

class VehicleDashboard {
  const VehicleDashboard({
    required this.vehicle,
    required this.currentOdometer,
    required this.recentOdometerEntries,
    required this.monthSpendMinor,
    required this.latestFuelPriceMicrosPerLitre,
    required this.latestFuelEconomyInterval,
    required this.recentActivity,
    required this.nextMaintenanceAttention,
    required this.spendingTrend,
  });

  final Vehicle vehicle;
  final int? currentOdometer;
  final List<OdometerEntry> recentOdometerEntries;
  final int monthSpendMinor;
  final int? latestFuelPriceMicrosPerLitre;
  final FuelEconomyInterval? latestFuelEconomyInterval;
  final List<DailyActivity> recentActivity;
  final MaintenanceReminder? nextMaintenanceAttention;
  final List<MonthlySpending> spendingTrend;
}
