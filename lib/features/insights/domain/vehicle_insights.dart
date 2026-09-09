import '../../../core/calculations/analytics_date_range.dart';
import '../../daily_records/domain/daily_activity.dart';
import '../../vehicles/domain/vehicle.dart';

class VehicleInsights {
  const VehicleInsights({
    required this.scope,
    required this.range,
    required this.fuelSpendMinor,
    required this.serviceSpendMinor,
    required this.expenseSpendMinor,
    required this.runningSpendMinor,
    required this.incomeMinor,
    required this.distance,
    required this.averageFuelEconomy,
    required this.averageFuelPriceMicrosPerLitre,
    required this.spendingBuckets,
    required this.breakdown,
    required this.fuelEconomyTrend,
    required this.fuelPriceTrend,
    required this.odometerTrend,
  });

  final InsightScope scope;
  final ResolvedAnalyticsRange range;
  final int fuelSpendMinor;
  final int serviceSpendMinor;
  final int expenseSpendMinor;
  final int runningSpendMinor;
  final int incomeMinor;
  final DistanceInsight distance;
  final FuelEconomyInsight averageFuelEconomy;
  final int? averageFuelPriceMicrosPerLitre;
  final List<InsightAmountBucket> spendingBuckets;
  final List<InsightBreakdownItem> breakdown;
  final List<FuelEconomyPoint> fuelEconomyTrend;
  final List<FuelPricePoint> fuelPriceTrend;
  final List<OdometerTrendPoint> odometerTrend;

  int get totalSpendMinor =>
      fuelSpendMinor + serviceSpendMinor + expenseSpendMinor;
  int get netMinor => incomeMinor - totalSpendMinor;
  bool get hasExpenditure => totalSpendMinor > 0;
  bool get hasIncome => incomeMinor > 0;
  bool get hasAnyData {
    return hasExpenditure ||
        hasIncome ||
        distance.value != null ||
        averageFuelEconomy.ukMpg != null ||
        averageFuelPriceMicrosPerLitre != null ||
        odometerTrend.isNotEmpty;
  }

  double? get runningCostMinorPerDistance {
    final value = distance.value;
    if (value == null || value <= 0) {
      return null;
    }
    return runningSpendMinor / value;
  }

  double? get totalCostMinorPerDistance {
    final value = distance.value;
    if (value == null || value <= 0) {
      return null;
    }
    return totalSpendMinor / value;
  }
}

class InsightScope {
  InsightScope.vehicle(Vehicle selectedVehicle)
    : isAllVehicles = false,
      vehicle = selectedVehicle,
      label = selectedVehicle.name,
      distanceUnit = selectedVehicle.distanceUnit;

  const InsightScope.allVehicles()
    : isAllVehicles = true,
      vehicle = null,
      label = 'All vehicles',
      distanceUnit = null;

  final bool isAllVehicles;
  final Vehicle? vehicle;
  final String label;
  final DistanceUnit? distanceUnit;
}

class DistanceInsight {
  const DistanceInsight.available(this.value, this.unit)
    : unavailableReason = null;

  const DistanceInsight.unavailable(this.unavailableReason)
    : value = null,
      unit = null;

  final int? value;
  final DistanceUnit? unit;
  final String? unavailableReason;

  bool get isAvailable => value != null && unit != null;
}

class FuelEconomyInsight {
  const FuelEconomyInsight.available({
    required this.ukMpg,
    required this.distance,
    required this.volumeMillilitres,
  }) : unavailableReason = null;

  const FuelEconomyInsight.unavailable(this.unavailableReason)
    : ukMpg = null,
      distance = 0,
      volumeMillilitres = 0;

  final double? ukMpg;
  final int distance;
  final int volumeMillilitres;
  final String? unavailableReason;

  bool get isAvailable => ukMpg != null;
}

class InsightAmountBucket {
  const InsightAmountBucket({
    required this.index,
    required this.startInclusive,
    required this.endExclusive,
    required this.label,
    required this.fuelSpendMinor,
    required this.serviceSpendMinor,
    required this.expenseSpendMinor,
    required this.incomeMinor,
  });

  final int index;
  final DateTime startInclusive;
  final DateTime endExclusive;
  final String label;
  final int fuelSpendMinor;
  final int serviceSpendMinor;
  final int expenseSpendMinor;
  final int incomeMinor;

  int get totalSpendMinor =>
      fuelSpendMinor + serviceSpendMinor + expenseSpendMinor;
  int get netMinor => incomeMinor - totalSpendMinor;
}

class InsightBreakdownItem {
  const InsightBreakdownItem({
    required this.key,
    required this.label,
    required this.amountMinor,
    required this.type,
    this.categoryId,
  });

  final String key;
  final String label;
  final int amountMinor;
  final DailyActivityType type;
  final String? categoryId;
}

class FuelEconomyPoint {
  const FuelEconomyPoint({
    required this.date,
    required this.label,
    required this.ukMpg,
    required this.distance,
    required this.volumeMillilitres,
  });

  final DateTime date;
  final String label;
  final double ukMpg;
  final int distance;
  final int volumeMillilitres;
}

class FuelPricePoint {
  const FuelPricePoint({
    required this.date,
    required this.label,
    required this.microsPerLitre,
  });

  final DateTime date;
  final String label;
  final int microsPerLitre;
}

class OdometerTrendPoint {
  const OdometerTrendPoint({
    required this.date,
    required this.label,
    required this.odometer,
  });

  final DateTime date;
  final String label;
  final int odometer;
}
