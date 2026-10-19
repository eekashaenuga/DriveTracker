import 'package:flutter/material.dart';

import '../../features/reminders/domain/date_reminder_schedule.dart';
import '../../app/theme/dt_tokens.dart';

class DateReminderEditor extends StatelessWidget {
  const DateReminderEditor({
    required this.value,
    required this.onChanged,
    this.showMotPreset = false,
    super.key,
  });
  final DateReminderSchedule value;
  final ValueChanged<DateReminderSchedule> onChanged;
  final bool showMotPreset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Date reminders', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: DTSpacing.sm),
        const Text(
          'Notifications at 9:00 AM local time. Mileage reminders stay in the app.',
        ),
        const SizedBox(height: DTSpacing.sm),
        Wrap(
          spacing: DTSpacing.sm,
          runSpacing: DTSpacing.sm,
          children: [
            for (var i = 0; i < value.offsets.length; i++)
              InputChip(
                label: Text(value.offsets[i].label),
                onDeleted: () => onChanged(
                  DateReminderSchedule(
                    offsets: [...value.offsets]..removeAt(i),
                    dailyFromDays: value.dailyFromDays,
                  ),
                ),
              ),
            if (value.dailyFromDays != null)
              InputChip(
                label: Text(
                  'Daily: ${value.dailyFromDays} days before through expiry/due day',
                ),
                onDeleted: () =>
                    onChanged(DateReminderSchedule(offsets: value.offsets)),
              ),
          ],
        ),
        Wrap(
          spacing: DTSpacing.sm,
          children: [
            TextButton.icon(
              key: const Key('addDateReminderButton'),
              onPressed: value.offsets.length >= 24
                  ? null
                  : () => _add(context),
              icon: const Icon(Icons.add),
              label: const Text('Add reminder'),
            ),
            TextButton(
              onPressed: () => onChanged(
                showMotPreset
                    ? DateReminderSchedule.mot
                    : DateReminderSchedule.standard,
              ),
              child: Text(showMotPreset ? 'MOT preset' : '30-day preset'),
            ),
            if (value.dailyFromDays == null)
              TextButton(
                onPressed: () => onChanged(
                  DateReminderSchedule(
                    offsets: value.offsets,
                    dailyFromDays: 7,
                  ),
                ),
                child: const Text('Daily final 7 days'),
              ),
          ],
        ),
        if (value.offsets.isEmpty && value.dailyFromDays == null)
          const Text(
            'No date notifications. The due status remains visible in the app.',
          ),
      ],
    );
  }

  Future<void> _add(BuildContext context) async {
    final amount = TextEditingController(text: '7');
    var unit = ReminderOffsetUnit.days;
    var countdown = false;
    String? error;
    final result = await showDialog<DateReminderSchedule>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          scrollable: true,
          title: const Text('Add reminder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('reminderOffsetAmount'),
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: countdown
                      ? 'Start days before (0–31)'
                      : 'Amount before (0 = on the day)',
                  errorText: error,
                ),
              ),
              DropdownButtonFormField<ReminderOffsetUnit>(
                initialValue: unit,
                decoration: const InputDecoration(labelText: 'Unit'),
                items: [
                  for (final u in ReminderOffsetUnit.values)
                    DropdownMenuItem(value: u, child: Text(u.name)),
                ],
                onChanged: countdown ? null : (u) => setState(() => unit = u!),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Repeat daily through due day'),
                value: countdown,
                onChanged: (v) => setState(() {
                  countdown = v;
                  unit = ReminderOffsetUnit.days;
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final n = int.tryParse(amount.text.trim());
                final next = n == null
                    ? null
                    : DateReminderSchedule(
                        offsets: countdown
                            ? value.offsets
                            : [...value.offsets, ReminderOffset(n, unit)],
                        dailyFromDays: countdown ? n : value.dailyFromDays,
                      );
                if (next == null || !next.isValid) {
                  setState(
                    () => error = countdown
                        ? 'Use 0–31 days.'
                        : 'Use 0–3650 days or 0–120 months.',
                  );
                  return;
                }
                Navigator.pop(context, next);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    if (result != null) onChanged(result);
  }
}
