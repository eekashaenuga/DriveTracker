import 'daily_activity.dart';

class HistoryCursor {
  const HistoryCursor(this.date, this.type, this.id);
  factory HistoryCursor.after(DailyActivity row) =>
      HistoryCursor(row.eventDateTime, row.type, row.recordId);
  final DateTime date;
  final DailyActivityType type;
  final String id;
}

class HistoryPage {
  const HistoryPage(this.records, this.next);
  final List<DailyActivity> records;
  final HistoryCursor? next;
}
