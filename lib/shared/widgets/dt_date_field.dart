import 'package:flutter/material.dart';

import '../../app/theme/dt_tokens.dart';

class DTDateField extends StatelessWidget {
  const DTDateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.currentDate,
    this.allowClear = true,
    this.fieldKey,
    super.key,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime? currentDate;
  final bool allowClear;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InputDecorator(
      key: fieldKey,
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value == null ? 'Not set' : compactDate(value!),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: value == null
                    ? colors.onSurfaceVariant
                    : colors.onSurface,
              ),
            ),
          ),
          if (allowClear && value != null)
            IconButton(
              tooltip: 'Clear $label',
              onPressed: () => onChanged(null),
              icon: const Icon(Icons.close_rounded),
            ),
          IconButton(
            tooltip: 'Choose $label',
            onPressed: () async {
              final now = currentDate ?? DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? now,
                firstDate: DateTime(1900),
                lastDate: DateTime(now.year + 20, 12, 31),
                currentDate: DateTime(now.year, now.month, now.day),
                initialEntryMode: DatePickerEntryMode.calendarOnly,
              );
              if (picked != null) {
                onChanged(DateTime(picked.year, picked.month, picked.day));
              }
            },
            icon: const Icon(Icons.calendar_month_rounded),
          ),
        ],
      ),
    );
  }
}

String compactDate(DateTime value) {
  final local = value.toLocal();
  return '${local.day} ${_monthShort(local.month)} ${local.year}';
}

String shortDate(DateTime value) {
  final local = value.toLocal();
  return '${local.day} ${_monthShort(local.month)}';
}

String _monthShort(int month) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return months[month - 1];
}

class DTInlineDateRange extends StatelessWidget {
  const DTInlineDateRange({
    required this.issueDate,
    required this.expiryDate,
    super.key,
  });

  final DateTime? issueDate;
  final DateTime? expiryDate;

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];
    if (issueDate != null) {
      parts.add(
        _DatePill(
          icon: Icons.event_available_rounded,
          label: compactDate(issueDate!),
        ),
      );
    }
    if (expiryDate != null) {
      parts.add(
        _DatePill(
          icon: Icons.event_busy_rounded,
          label: compactDate(expiryDate!),
        ),
      );
    }
    if (parts.isEmpty) {
      parts.add(
        const _DatePill(icon: Icons.event_note_rounded, label: 'No dates'),
      );
    }
    return Wrap(
      spacing: DTSpacing.sm,
      runSpacing: DTSpacing.sm,
      children: parts,
    );
  }
}

class _DatePill extends StatelessWidget {
  const _DatePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DTSpacing.sm,
        vertical: DTSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(DTRadii.card),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: DTIconSizes.sm, color: colors.onSurfaceVariant),
          const SizedBox(width: DTSpacing.xs),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}
