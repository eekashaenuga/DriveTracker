import 'package:flutter/material.dart';

class DTDropdownOption<T> {
  const DTDropdownOption({required this.value, required this.label});

  final T value;
  final String label;
}

class DTEditableDropdownFormField<T> extends StatelessWidget {
  const DTEditableDropdownFormField({
    required this.options,
    this.initialValue,
    this.decoration = const InputDecoration(),
    this.validator,
    this.onChanged,
    this.invalidSelectionErrorText = 'Choose a listed option.',
    super.key,
  });

  final List<DTDropdownOption<T>> options;
  final T? initialValue;
  final InputDecoration decoration;
  final FormFieldValidator<T>? validator;
  final ValueChanged<T?>? onChanged;
  final String invalidSelectionErrorText;

  @override
  Widget build(BuildContext context) {
    final selectedOption = _optionForValue(initialValue);
    final initialText = selectedOption?.label ?? '';
    final isEnabled = onChanged != null;

    return Autocomplete<DTDropdownOption<T>>(
      key: ValueKey<String>(_stateSignature(initialText, isEnabled)),
      initialValue: TextEditingValue(text: initialText),
      displayStringForOption: (option) => option.label,
      optionsBuilder: (textEditingValue) {
        if (!isEnabled) {
          return const Iterable<DTDropdownOption<T>>.empty();
        }
        final query = _normalize(textEditingValue.text);
        if (query.isEmpty || query == _normalize(initialText)) {
          return options;
        }
        return options.where(
          (option) => _normalize(option.label).contains(query),
        );
      },
      onSelected: (option) => onChanged?.call(option.value),
      fieldViewBuilder:
          (context, textController, focusNode, onFieldSubmitted) {
            return TextFormField(
              controller: textController,
              focusNode: focusNode,
              enabled: isEnabled,
              decoration: decoration.copyWith(
                suffixIcon:
                    decoration.suffixIcon ??
                    Icon(
                      Icons.expand_more_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              textInputAction: TextInputAction.next,
              validator: (text) {
                if (!isEnabled) {
                  return null;
                }
                final selectedValue = _optionForLabel(text ?? '')?.value;
                final validationMessage = validator?.call(selectedValue);
                if (validationMessage != null) {
                  return validationMessage;
                }
                return selectedValue == null ? invalidSelectionErrorText : null;
              },
              onChanged: (text) {
                final option = _optionForLabel(text);
                if (option != null) {
                  onChanged?.call(option.value);
                }
              },
            );
          },
    );
  }

  DTDropdownOption<T>? _optionForValue(T? value) {
    if (value == null) {
      return null;
    }
    for (final option in options) {
      if (option.value == value) {
        return option;
      }
    }
    return null;
  }

  DTDropdownOption<T>? _optionForLabel(String label) {
    final normalizedLabel = _normalize(label);
    if (normalizedLabel.isEmpty) {
      return null;
    }
    for (final option in options) {
      if (_normalize(option.label) == normalizedLabel) {
        return option;
      }
    }
    return null;
  }

  String _stateSignature(String initialText, bool isEnabled) {
    final optionSignature = options
        .map((option) => '${option.value}:${option.label}')
        .join('|');
    return '$isEnabled|$initialText|$optionSignature';
  }
}

String _normalize(String value) => value.trim().toLowerCase();
