import 'dart:convert';

/// Calendar offsets, independent of OS notification identifiers and time zones.
enum ReminderOffsetUnit { days, months }

class ReminderOffset {
  const ReminderOffset(this.amount, [this.unit = ReminderOffsetUnit.days]);
  final int amount;
  final ReminderOffsetUnit unit;
  String get label =>
      amount == 0 ? 'On the day' : '$amount ${unit.name} before';
  Map<String, Object> toMap() => {'amount': amount, 'unit': unit.name};
}

class DateReminderSchedule {
  const DateReminderSchedule({this.offsets = const [], this.dailyFromDays});
  static const mot = DateReminderSchedule(
    offsets: [
      ReminderOffset(3, ReminderOffsetUnit.months),
      ReminderOffset(1, ReminderOffsetUnit.months),
      ReminderOffset(15),
      ReminderOffset(7),
    ],
    dailyFromDays: 7,
  );
  static const standard = DateReminderSchedule(offsets: [ReminderOffset(30)]);

  final List<ReminderOffset> offsets;

  /// Inclusive countdown, ending on the due/expiry day. Null disables it.
  final int? dailyFromDays;

  bool get isEnabled => offsets.isNotEmpty || dailyFromDays != null;

  bool get isValid =>
      offsets.length <= 24 &&
      offsets.every(
        (o) =>
            o.amount >= 0 &&
            o.amount <= (o.unit == ReminderOffsetUnit.days ? 3650 : 120),
      ) &&
      (dailyFromDays == null || (dailyFromDays! >= 0 && dailyFromDays! <= 31));

  String get summary => offsets.isEmpty && dailyFromDays == null
      ? 'No date notifications'
      : [
          ...offsets.map((o) => o.label),
          if (dailyFromDays != null)
            'Daily from $dailyFromDays days before through the day',
        ].join(', ');

  String toJson() => jsonEncode({
    'offsets': offsets.map((o) => o.toMap()).toList(),
    'dailyFromDays': dailyFromDays,
  });

  static DateReminderSchedule? fromJson(Object? value) {
    if (value == null) return null; // V4 single-warning behaviour.
    final map = jsonDecode(value as String) as Map<String, dynamic>;
    final result = DateReminderSchedule(
      offsets: [
        for (final entry in map['offsets'] as List)
          ReminderOffset(
            entry['amount'] as int,
            ReminderOffsetUnit.values.byName(entry['unit'] as String),
          ),
      ],
      dailyFromDays: map['dailyFromDays'] as int?,
    );
    if (!result.isValid) {
      throw const FormatException('Invalid reminder schedule');
    }
    return result;
  }

  /// Every result is a unique future local 09:00 appointment. Calendar month
  /// subtraction clamps to the last day, rather than treating a month as 30 days.
  List<DateTime> notificationTimes(DateTime due, DateTime now) {
    if (!isValid) {
      throw const FormatException('Invalid reminder schedule');
    }
    final days = <String, DateTime>{};
    void add(int year, int month, int day) {
      final at = DateTime(year, month, day, 9);
      if (at.isAfter(now.toLocal())) {
        days['${at.year}-${at.month}-${at.day}'] = at;
      }
    }

    void addDays(int offset) {
      final date = DateTime.utc(due.year, due.month, due.day - offset);
      add(date.year, date.month, date.day);
    }

    for (final offset in offsets) {
      if (offset.unit == ReminderOffsetUnit.days) {
        addDays(offset.amount);
      } else {
        final month = DateTime.utc(due.year, due.month - offset.amount);
        final lastDay = DateTime.utc(month.year, month.month + 1, 0).day;
        add(month.year, month.month, due.day > lastDay ? lastDay : due.day);
      }
    }
    final countdown = dailyFromDays;
    if (countdown != null) {
      for (var day = countdown; day >= 0; day--) {
        addDays(day);
      }
    }
    return days.values.toList()..sort();
  }
}

int calendarDaysBetween(DateTime due, DateTime asOf) {
  final localNow = asOf.toLocal();
  return DateTime.utc(due.year, due.month, due.day)
      .difference(DateTime.utc(localNow.year, localNow.month, localNow.day))
      .inDays;
}
