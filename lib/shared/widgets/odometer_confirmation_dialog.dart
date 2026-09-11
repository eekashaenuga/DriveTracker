import 'package:flutter/material.dart';

import '../../core/utilities/formatters.dart';
import '../../features/odometer/domain/odometer_policy.dart';
import '../../features/vehicles/domain/vehicle.dart';

Future<bool> showOdometerConfirmationDialog({
  required BuildContext context,
  required OdometerAssessment assessment,
  required DistanceUnit unit,
  required String historicalTitle,
}) async {
  final isHistorical = assessment.decision == OdometerDecision.belowCurrent;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: Key(
        isHistorical
            ? 'odometerHistoricalConfirmDialog'
            : 'odometerHighJumpConfirmDialog',
      ),
      title: Text(
        isHistorical ? historicalTitle : 'Unusually high odometer reading',
      ),
      content: Text(
        isHistorical
            ? assessment.message
            : 'This reading is ${DTFormatters.odometer(assessment.difference, unit)} above the previous reading. Please check that the mileage is correct before saving.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(isHistorical ? 'Cancel' : 'Go back'),
        ),
        FilledButton(
          key: Key(
            isHistorical
                ? 'confirmHistoricalOdometerButton'
                : 'confirmHighOdometerButton',
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(isHistorical ? 'Save historical' : 'Save anyway'),
        ),
      ],
    ),
  );
  return result ?? false;
}
