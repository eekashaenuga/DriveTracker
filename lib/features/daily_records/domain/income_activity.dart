import '../../../core/utilities/scaled_decimal.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../vehicles/domain/vehicle.dart';

enum IncomeActivityType {
  simple('Simple / Other'),
  rideshare('Rideshare'),
  delivery('Delivery shift'),
  work('Work / Salary'),
  reimbursement('Mileage reimbursement');

  const IncomeActivityType(this.label);
  final String label;
  bool get hasBreakdown =>
      this == rideshare || this == delivery || this == work;
  static IncomeActivityType suggested(String? categoryId) =>
      switch (categoryId) {
        'cat_income_rideshare' => rideshare,
        'cat_income_delivery' => delivery,
        'cat_income_mileage_reimbursement' => reimbursement,
        _ => simple,
      };
}

class ActivityDistance {
  const ActivityDistance._();
  static int scale(DistanceUnit unit) =>
      unit == DistanceUnit.miles ? 1609344 : 1000000;
  static int? parse(String text, DistanceUnit unit) {
    // Input precision is three decimal places; conversion rounds only once to mm.
    final thousandths = ScaledDecimal.parse(text, scale: 1000);
    return thousandths == null
        ? null
        : (thousandths * scale(unit) + 500) ~/ 1000;
  }

  static double value(int mm, DistanceUnit unit) => mm / scale(unit);
  static String input(int? mm, DistanceUnit unit) =>
      mm == null ? '' : value(mm, unit).toStringAsFixed(3);
}

class IncomeActivity {
  const IncomeActivity({
    this.type = IncomeActivityType.simple,
    this.baseMinor,
    this.tipsMinor,
    this.travelMinor,
    this.otherMinor,
    this.distanceMm,
    this.durationMinutes,
    this.deliveryCount,
    this.rateMicros,
    this.rateUnit,
    this.directCostsComplete = false,
  });
  final IncomeActivityType type;
  final int? baseMinor,
      tipsMinor,
      travelMinor,
      otherMinor,
      distanceMm,
      durationMinutes,
      deliveryCount,
      rateMicros;
  final DistanceUnit? rateUnit;
  final bool directCostsComplete;
  bool get hasBreakdown =>
      [baseMinor, tipsMinor, travelMinor, otherMinor].any((v) => v != null);
  void validate(int gross) {
    void fail(String message) => throw ValidationException([message]);
    if (hasBreakdown &&
        (!type.hasBreakdown ||
            [
              baseMinor,
              tipsMinor,
              travelMinor,
              otherMinor,
            ].any((v) => v == null || v < 0) ||
            baseMinor! + tipsMinor! + travelMinor! + otherMinor! != gross)) {
      fail(
        'Enter all four breakdown amounts (zero is allowed). Their sum must equal gross received.',
      );
    }
    for (final value in [
      distanceMm,
      durationMinutes,
      deliveryCount,
      rateMicros,
    ]) {
      if (value != null && value <= 0) {
        fail(
          'Activity distance, duration, count and rate must be greater than zero when supplied.',
        );
      }
    }
    if ((rateMicros == null) != (rateUnit == null)) {
      fail('Enter both reimbursement rate and its unit.');
    }
    if (type == IncomeActivityType.simple &&
        (distanceMm != null ||
            durationMinutes != null ||
            deliveryCount != null ||
            rateMicros != null ||
            directCostsComplete)) {
      fail('Simple income does not use activity fields.');
    }
    if (type != IncomeActivityType.delivery && deliveryCount != null) {
      fail('Delivery count is only available for a delivery shift.');
    }
    if (type != IncomeActivityType.reimbursement && rateMicros != null) {
      fail('A reimbursement rate is only available for mileage reimbursement.');
    }
    if (type == IncomeActivityType.reimbursement && durationMinutes != null) {
      fail('Mileage reimbursement does not use duration.');
    }
  }

  Map<String, Object?> toMap() => {
    'activity_type': type.name,
    'base_amount_minor': baseMinor,
    'tips_minor': tipsMinor,
    'travel_compensation_minor': travelMinor,
    'other_income_minor': otherMinor,
    'activity_distance_mm': distanceMm,
    'duration_minutes': durationMinutes,
    'delivery_count': deliveryCount,
    'reimbursement_rate_micros': rateMicros,
    'reimbursement_rate_unit': rateUnit?.storageValue,
    'direct_costs_complete': directCostsComplete ? 1 : 0,
  };
  factory IncomeActivity.fromMap(Map<String, Object?> map) => IncomeActivity(
    type: IncomeActivityType.values.byName(
      map['activity_type'] as String? ?? 'simple',
    ),
    baseMinor: map['base_amount_minor'] as int?,
    tipsMinor: map['tips_minor'] as int?,
    travelMinor: map['travel_compensation_minor'] as int?,
    otherMinor: map['other_income_minor'] as int?,
    distanceMm: map['activity_distance_mm'] as int?,
    durationMinutes: map['duration_minutes'] as int?,
    deliveryCount: map['delivery_count'] as int?,
    rateMicros: map['reimbursement_rate_micros'] as int?,
    rateUnit: map['reimbursement_rate_unit'] == null
        ? null
        : DistanceUnit.fromStorage(map['reimbursement_rate_unit'] as String),
    directCostsComplete: map['direct_costs_complete'] == 1,
  );
}
