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
}
