import '../../../core/calculations/cost_per_distance.dart';
import 'income.dart';
import 'income_activity.dart';
import '../../vehicles/domain/vehicle.dart';

class IncomeEarnings {
  const IncomeEarnings(this.income, this.directCostsMinor);
  final Income income;
  final int directCostsMinor;
  IncomeActivity get activity => income.activity;
  int? get netMinor => activity.directCostsComplete
      ? income.amountMinor - directCostsMinor
      : null;
  double? grossPerDistance(DistanceUnit unit) => CostPerDistance.calculate(
    costMinor: income.amountMinor,
    distance: ActivityDistance.value(activity.distanceMm ?? 0, unit),
  );
  double? netPerDistance(DistanceUnit unit) =>
      _ratio(netMinor, ActivityDistance.value(activity.distanceMm ?? 0, unit));
  double? get grossPerHour =>
      _ratio(income.amountMinor, (activity.durationMinutes ?? 0) / 60);
  double? get netPerHour =>
      _ratio(netMinor, (activity.durationMinutes ?? 0) / 60);
  double? get perDelivery =>
      _ratio(income.amountMinor, (activity.deliveryCount ?? 0).toDouble());
  int? get expectedClaimMinor {
    if (activity.distanceMm == null ||
        activity.rateMicros == null ||
        activity.rateUnit == null) {
      return null;
    }
    final denominator = ActivityDistance.scale(activity.rateUnit!) * 10000;
    final numerator = activity.distanceMm! * activity.rateMicros!;
    return (numerator + denominator ~/ 2) ~/ denominator;
  }

  static double? _ratio(num? amount, double denominator) =>
      amount == null || denominator <= 0 ? null : amount / denominator;
}

class EarningsSummary {
  EarningsSummary(Iterable<IncomeEarnings> records)
    : records = records.toList();
  final List<IncomeEarnings> records;
  int get count => records.length;
  int get grossMinor => records.fold(0, (s, r) => s + r.income.amountMinor);
  int get recordedCostsMinor =>
      records.fold(0, (s, r) => s + r.directCostsMinor);
  int get completeCount => records.where((r) => r.netMinor != null).length;
  int? get netMinor => count > 0 && completeCount == count
      ? grossMinor - recordedCostsMinor
      : null;
  int get distanceCount =>
      records.where((r) => r.activity.distanceMm != null).length;
  int get durationCount =>
      records.where((r) => r.activity.durationMinutes != null).length;
  int get deliveryCount =>
      records.where((r) => r.activity.deliveryCount != null).length;
  int get netDistanceCount => records
      .where((r) => r.netMinor != null && r.activity.distanceMm != null)
      .length;
  int get netDurationCount => records
      .where((r) => r.netMinor != null && r.activity.durationMinutes != null)
      .length;
  double? perDistance(DistanceUnit unit, {bool net = false}) => _aggregate(
    (r) => r.activity.distanceMm == null
        ? null
        : ActivityDistance.value(r.activity.distanceMm!, unit),
    net: net,
  );
  double? perHour({bool net = false}) => _aggregate(
    (r) => r.activity.durationMinutes == null
        ? null
        : r.activity.durationMinutes! / 60,
    net: net,
  );
  double? get perDelivery =>
      _aggregate((r) => r.activity.deliveryCount?.toDouble());
  double? _aggregate(
    double? Function(IncomeEarnings) denominator, {
    bool net = false,
  }) {
    var amount = 0;
    var total = 0.0;
    for (final r in records) {
      final d = denominator(r);
      final a = net ? r.netMinor : r.income.amountMinor;
      if (d == null || d <= 0 || a == null) continue;
      amount += a;
      total += d;
    }
    return total <= 0 ? null : amount / total;
  }
}
