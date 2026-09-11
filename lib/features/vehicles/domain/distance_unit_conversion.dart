import 'vehicle.dart';

class DistanceUnitConversion {
  const DistanceUnitConversion._();

  static const kilometersPerMile = 1.609344;

  static double factor({required DistanceUnit from, required DistanceUnit to}) {
    if (from == to) {
      return 1;
    }
    return switch ((from, to)) {
      (DistanceUnit.miles, DistanceUnit.kilometers) => kilometersPerMile,
      (DistanceUnit.kilometers, DistanceUnit.miles) => 1 / kilometersPerMile,
      _ => 1,
    };
  }

  static int convertWholeDistance(
    int value, {
    required DistanceUnit from,
    required DistanceUnit to,
  }) {
    return (value * factor(from: from, to: to)).round();
  }
}
