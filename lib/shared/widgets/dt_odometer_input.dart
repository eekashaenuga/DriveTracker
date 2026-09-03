import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DTOdometerInput extends StatelessWidget {
  const DTOdometerInput({
    required this.controller,
    required this.unitLabel,
    this.label = 'Odometer',
    this.fieldKey,
    this.onChanged,
    this.validator,
    this.textInputAction,
    super.key,
  });

  final TextEditingController controller;
  final String unitLabel;
  final String label;
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
      decoration: InputDecoration(labelText: label, suffixText: unitLabel),
      validator: validator,
      onChanged: onChanged,
    );
  }
}
