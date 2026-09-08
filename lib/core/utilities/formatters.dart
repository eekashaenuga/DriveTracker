import '../../features/vehicles/domain/vehicle.dart';
import 'money.dart';

class DTFormatters {
  const DTFormatters._();

  static String wholeNumber(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }

  static String odometer(int? value, DistanceUnit unit) {
    if (value == null) {
      return 'No reading yet';
    }

    return '${wholeNumber(value)} ${unit.shortLabel}';
  }

  static String signedDistance(int value, DistanceUnit unit) {
    final sign = value > 0 ? '+' : '';
    return '$sign${wholeNumber(value)} ${unit.shortLabel}';
  }

  static String dateTime(DateTime value) {
    final local = value.toLocal();
    final date = '${local.year}-${_two(local.month)}-${_two(local.day)}';
    final time = '${_two(local.hour)}:${_two(local.minute)}';
    return '$date $time';
  }

  static String date(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${_two(local.month)}-${_two(local.day)}';
  }

  static String activityDateTime(DateTime value, {DateTime? now}) {
    final local = value.toLocal();
    final localNow = (now ?? DateTime.now()).toLocal();
    final eventDay = DateTime(local.year, local.month, local.day);
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final dayDifference = today.difference(eventDay).inDays;
    return switch (dayDifference) {
      0 => 'Today, ${_twelveHourTime(local)}',
      1 => 'Yesterday, ${_twelveHourTime(local)}',
      _ =>
        local.year == localNow.year
            ? '${local.day} ${_monthShort(local.month)}'
            : '${local.day} ${_monthShort(local.month)} ${local.year}',
    };
  }

  static String moneyMinor(int? value) {
    return MoneyAmount.formatMinor(value);
  }

  static String fuelVolume(int? millilitres) {
    return FuelNumbers.formatLitres(millilitres);
  }

  static String fuelPrice(int? microsPerLitre) {
    return FuelNumbers.formatPencePerLitre(microsPerLitre);
  }

  static String ukMpg(double? value) {
    return FuelNumbers.formatUkMpg(value);
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _monthShort(int month) {
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

  static String _twelveHourTime(DateTime value) {
    final period = value.hour >= 12 ? 'PM' : 'AM';
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    return '$hour:${_two(value.minute)} $period';
  }
}
