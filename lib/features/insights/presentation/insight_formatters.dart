import '../../../core/calculations/analytics_date_range.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/utilities/money.dart';
import '../../vehicles/domain/vehicle.dart';

/// Display-only rounding. Never use these strings as calculation inputs.
class InsightFormat {
  const InsightFormat._();

  static const _months = [
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

  static String date(DateTime? value, {bool compact = false}) {
    if (value == null) {
      return 'Not recorded';
    }
    final local = value.toLocal();
    return '${local.day} ${_months[local.month - 1]}${compact ? '' : ' ${local.year}'}';
  }

  static String range(DateTime start, DateTime end) =>
      '${date(start)} – ${date(end)}';

  static String customRange(AnalyticsDateRange range) {
    final start = range.customStart;
    final end = range.customEndInclusive;
    if (start == null || end == null) {
      return 'Custom';
    }
    return start == end ? date(start) : InsightFormat.range(start, end);
  }

  // Round scaled integers exactly, only at the display boundary.
  static String _twoDecimalScaled(int value, int scale) {
    final hundredths = (value.abs() * 100 + scale ~/ 2) ~/ scale;
    return '${value < 0 ? '-' : ''}${hundredths ~/ 100}.${(hundredths % 100).toString().padLeft(2, '0')}';
  }

  static String litres(int? millilitres) => millilitres == null
      ? '-'
      : '${_twoDecimalScaled(millilitres, FuelNumbers.millilitresPerLitre)} L';

  static String price(int? microsPerLitre) => microsPerLitre == null
      ? '-'
      : '${_twoDecimalScaled(microsPerLitre, FuelNumbers.microsPerPence)} p/L';

  static String economy(double? mpg) => DTFormatters.ukMpg(mpg);

  static String distance(num? value) {
    if (value == null || !value.isFinite) {
      return 'Unavailable';
    }
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static String costPerDistance(double? minor, DistanceUnit? unit) =>
      DTFormatters.costPerDistance(minor, unit).replaceAll('/', ' / ');
}
