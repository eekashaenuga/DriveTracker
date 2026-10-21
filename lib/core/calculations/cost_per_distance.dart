/// Rates use minor currency units, divided before display rounding.
class CostPerDistance {
  const CostPerDistance._();

  static double? calculate({required num costMinor, required num distance}) {
    if (!costMinor.isFinite ||
        costMinor < 0 ||
        !distance.isFinite ||
        distance <= 0) {
      return null;
    }
    final rate = costMinor / distance;
    return rate.isFinite ? rate : null;
  }
}
