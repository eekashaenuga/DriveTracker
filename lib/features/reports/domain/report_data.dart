import '../../insights/presentation/insight_formatters.dart';

enum ReportValueType { text, number, money, date, timestamp }

class ReportColumn {
  const ReportColumn(
    this.label, {
    this.type = ReportValueType.text,
    this.precision = 2,
    this.width = 24,
  });
  final String label;
  final ReportValueType type;
  final int precision;
  final double width;
}

class ReportTable {
  ReportTable(
    this.name,
    List<ReportColumn> columns,
    Iterable<List<Object?>> rows, {
    this.caption = '',
  }) : columns = List.unmodifiable(columns),
       rows = List.unmodifiable(rows.map((r) => List<Object?>.unmodifiable(r)));
  final String name, caption;
  final List<ReportColumn> columns;
  final List<List<Object?>> rows;
}

class ReportMetric {
  const ReportMetric(
    this.label,
    this.value, {
    this.type = ReportValueType.text,
    this.note = '',
  });
  final String label, note;
  final Object? value;
  final ReportValueType type;
}

class ReportData {
  ReportData({
    required this.vehicleName,
    required this.period,
    required this.generatedAt,
    required this.timezone,
    required List<ReportMetric> identity,
    required Map<String, ReportMetric> metrics,
    required List<ReportTable> tables,
    required List<ReportMetric> breakdown,
    required this.recordCount,
  }) : identity = List.unmodifiable(identity),
       metrics = Map.unmodifiable(metrics),
       tables = List.unmodifiable(tables),
       breakdown = List.unmodifiable(breakdown);
  final String vehicleName, period, timezone;
  final DateTime generatedAt;
  final List<ReportMetric> identity, breakdown;
  final Map<String, ReportMetric> metrics;
  final List<ReportTable> tables;
  final int recordCount;
}

String reportDisplay(Object? value, ReportValueType type, {int precision = 2}) {
  if (value == null) return 'Not available';
  if (type == ReportValueType.money) {
    return '£${((value as num) / 100).toStringAsFixed(2)}';
  }
  if (value is DateTime) {
    final d = value.toLocal();
    return '${InsightFormat.date(d)}${type == ReportValueType.timestamp ? ' ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}' : ''}';
  }
  if (value is double) return value.toStringAsFixed(precision);
  return value.toString();
}
