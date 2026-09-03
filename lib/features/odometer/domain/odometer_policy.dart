enum OdometerDecision {
  accepted,
  belowCurrent,
  unusuallyLargeIncrease,
  invalid,
}

class OdometerAssessment {
  const OdometerAssessment({
    required this.decision,
    required this.difference,
    required this.message,
  });

  final OdometerDecision decision;
  final int difference;
  final String message;

  bool get needsConfirmation {
    return decision == OdometerDecision.belowCurrent ||
        decision == OdometerDecision.unusuallyLargeIncrease;
  }
}

class OdometerPolicy {
  const OdometerPolicy({this.largeIncreaseThreshold = 50000});

  final int largeIncreaseThreshold;

  OdometerAssessment assess({
    required int? currentOdometer,
    required int newOdometer,
  }) {
    if (newOdometer < 0) {
      return const OdometerAssessment(
        decision: OdometerDecision.invalid,
        difference: 0,
        message: 'Odometer readings cannot be negative.',
      );
    }

    final current = currentOdometer ?? 0;
    final difference = newOdometer - current;

    if (currentOdometer != null && difference < 0) {
      return OdometerAssessment(
        decision: OdometerDecision.belowCurrent,
        difference: difference,
        message: 'This reading is below the vehicle current odometer. Save it as a historical reading?',
      );
    }

    if (currentOdometer != null && difference > largeIncreaseThreshold) {
      return OdometerAssessment(
        decision: OdometerDecision.unusuallyLargeIncrease,
        difference: difference,
        message: 'This is a large odometer increase. Confirm the reading before saving.',
      );
    }

    return OdometerAssessment(
      decision: OdometerDecision.accepted,
      difference: difference,
      message: 'Ready to update odometer.',
    );
  }
}

class OdometerConfirmationRequired implements Exception {
  const OdometerConfirmationRequired(this.assessment);

  final OdometerAssessment assessment;

  @override
  String toString() => assessment.message;
}
