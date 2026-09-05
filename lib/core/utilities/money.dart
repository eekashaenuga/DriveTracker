import 'scaled_decimal.dart';

class CurrencySpec {
  const CurrencySpec({
    required this.code,
    required this.symbol,
    required this.minorDigits,
  });

  final String code;
  final String symbol;
  final int minorDigits;

  int get minorScale => _pow10(minorDigits);

  static const gbp = CurrencySpec(code: 'GBP', symbol: '£', minorDigits: 2);

  static int _pow10(int exponent) {
    var value = 1;
    for (var index = 0; index < exponent; index += 1) {
      value *= 10;
    }
    return value;
  }
}

class MoneyAmount {
  const MoneyAmount._();

  static const defaultCurrency = CurrencySpec.gbp;

  static int? parseMinor(
    String value, {
    CurrencySpec currency = defaultCurrency,
  }) {
    return ScaledDecimal.parse(value, scale: currency.minorScale);
  }

  static String formatMinor(
    int? minor, {
    CurrencySpec currency = defaultCurrency,
    String empty = '-',
  }) {
    if (minor == null) {
      return empty;
    }

    final value = ScaledDecimal.format(
      minor,
      scale: currency.minorScale,
      minFractionDigits: currency.minorDigits,
      maxFractionDigits: currency.minorDigits,
    );
    return '${currency.symbol}$value';
  }
}

class FuelNumbers {
  const FuelNumbers._();

  static const millilitresPerLitre = 1000;
  static const microsPerMajorUnit = 1000000;
  static const microsPerPence = 10000;
  static const pencePerMajorUnit = 100;
  static const imperialGallonsPerLitre = 0.219969;

  static int? parseLitresToMillilitres(String value) {
    return ScaledDecimal.parse(value, scale: millilitresPerLitre);
  }

  static int? parsePencePerLitreToMicros(String value) {
    return ScaledDecimal.parse(value, scale: microsPerPence);
  }

  static int? parsePoundsPerLitreToMicros(String value) {
    return ScaledDecimal.parse(value, scale: microsPerMajorUnit);
  }

  static String formatLitres(int? millilitres, {String empty = '-'}) {
    if (millilitres == null) {
      return empty;
    }
    return '${ScaledDecimal.format(millilitres, scale: millilitresPerLitre, maxFractionDigits: 3)} L';
  }

  static String formatPencePerLitre(int? micros, {String empty = '-'}) {
    if (micros == null) {
      return empty;
    }
    return '${ScaledDecimal.format(micros, scale: microsPerPence, maxFractionDigits: 3)} p/L';
  }

  static String formatPoundsPerLitre(int? micros, {String empty = '-'}) {
    if (micros == null) {
      return empty;
    }
    return '${MoneyAmount.defaultCurrency.symbol}${ScaledDecimal.format(micros, scale: microsPerMajorUnit, minFractionDigits: 3, maxFractionDigits: 3)}/L';
  }

  static String formatUkMpg(double? value, {String empty = 'Not enough data'}) {
    if (value == null || value.isNaN || value.isInfinite) {
      return empty;
    }
    return '${value.toStringAsFixed(1)} UK MPG';
  }
}
