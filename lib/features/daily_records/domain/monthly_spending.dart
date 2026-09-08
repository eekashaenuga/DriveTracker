class MonthlySpending {
  const MonthlySpending({required this.month, required this.amountMinor});

  final DateTime month;
  final int amountMinor;

  bool get hasSpend => amountMinor > 0;
}
