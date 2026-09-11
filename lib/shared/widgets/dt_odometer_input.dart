import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utilities/formatters.dart';
import '../../features/vehicles/domain/vehicle.dart';

class DTOdometerInput extends StatelessWidget {
  const DTOdometerInput({
    required this.controller,
    required this.unitLabel,
    this.label = 'Odometer',
    this.helperText,
    this.fieldKey,
    this.onChanged,
    this.validator,
    this.textInputAction,
    super.key,
  });

  final TextEditingController controller;
  final String unitLabel;
  final String label;
  final String? helperText;
  final Key? fieldKey;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: fieldKey,
      controller: controller,
      keyboardType: TextInputType.number,
      textInputAction: textInputAction,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]'))],
      decoration: InputDecoration(
        labelText: label,
        suffixText: unitLabel,
        helperText: helperText,
        helperMaxLines: 2,
      ),
      validator: validator,
      onChanged: onChanged,
    );
  }
}

int? dtParseOdometerInput(String value) {
  final normalized = value.replaceAll(',', '').trim();
  if (normalized.isEmpty) {
    return null;
  }
  return int.tryParse(normalized);
}

String? dtOdometerContextText({
  required int? referenceOdometer,
  required DistanceUnit? unit,
  required int? enteredOdometer,
  String referenceLabel = 'Last recorded',
}) {
  if (referenceOdometer == null || unit == null) {
    return null;
  }

  final reference = DTFormatters.odometer(referenceOdometer, unit);
  final difference = enteredOdometer == null
      ? null
      : enteredOdometer - referenceOdometer;
  if (difference == null || difference == 0) {
    return '$referenceLabel: $reference';
  }
  return '$referenceLabel: $reference (${DTFormatters.signedDistance(difference, unit)})';
}
