import '../../../core/calculations/analytics_date_range.dart';

enum ReportSection {
  fuel('Fuel'),
  services('Services'),
  expenses('Expenses'),
  income('Income / Activities'),
  odometer('Odometer'),
  documents('Documents');

  const ReportSection(this.label);
  final String label;
}

enum ReportFormat { xlsx, pdf }

class ReportRequest {
  ReportRequest({
    required this.vehicleId,
    required this.range,
    required Set<ReportSection> sections,
    required this.format,
    this.includeSensitive = false,
  }) : sections = Set.unmodifiable(sections);
  final String vehicleId;
  final AnalyticsDateRange range;
  final Set<ReportSection> sections;
  final ReportFormat format;
  final bool includeSensitive;
}

class ReportException implements Exception {
  const ReportException(this.message);
  final String message;
  @override
  String toString() => message;
}
