enum DailyActivityType {
  all('All'),
  refuel('Fuel'),
  expense('Expense'),
  income('Income'),
  odometer('Odometer');

  const DailyActivityType(this.label);

  final String label;
}

class DailyActivity {
  const DailyActivity({
    required this.type,
    required this.recordId,
    required this.vehicleId,
    required this.eventDateTime,
    required this.createdAt,
    required this.title,
    required this.subtitle,
    this.amountMinor,
    this.odometer,
  });

  final DailyActivityType type;
  final String recordId;
  final String vehicleId;
  final DateTime eventDateTime;
  final DateTime createdAt;
  final String title;
  final String subtitle;
  final int? amountMinor;
  final int? odometer;
}
