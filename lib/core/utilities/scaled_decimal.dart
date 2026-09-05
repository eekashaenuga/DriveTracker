class ScaledDecimal {
  const ScaledDecimal._();

  static int? parse(String value, {required int scale}) {
    final normalized = value
        .trim()
        .replaceAll(',', '')
        .replaceAll('£', '')
        .replaceAll('p/L', '')
        .replaceAll('/L', '')
        .trim();
    if (normalized.isEmpty) {
      return null;
    }

    final match = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(normalized);
    if (match == null) {
      return null;
    }

    final whole = int.parse(match.group(1)!);
    final fraction = match.group(2) ?? '';
    final places = _decimalPlaces(scale);
    var scaledFraction = 0;
    if (places > 0) {
      final padded = fraction.padRight(places, '0');
      scaledFraction = int.parse(padded.substring(0, places));
      if (fraction.length > places && int.parse(fraction[places]) >= 5) {
        scaledFraction += 1;
      }
    } else if (fraction.isNotEmpty && int.parse(fraction[0]) >= 5) {
      return whole + 1;
    }

    return whole * scale + scaledFraction;
  }

  static String format(
    int value, {
    required int scale,
    int minFractionDigits = 0,
    int maxFractionDigits = 2,
  }) {
    final whole = value ~/ scale;
    final remainder = value.abs() % scale;
    final places = _decimalPlaces(scale);
    if (places == 0 || maxFractionDigits == 0) {
      return whole.toString();
    }

    final rawFraction = remainder.toString().padLeft(places, '0');
    final fractionLength = maxFractionDigits.clamp(0, places).toInt();
    final capped = rawFraction.substring(0, fractionLength);
    var fraction = capped;
    while (fraction.length > minFractionDigits && fraction.endsWith('0')) {
      fraction = fraction.substring(0, fraction.length - 1);
    }

    if (fraction.isEmpty) {
      return whole.toString();
    }
    return '$whole.$fraction';
  }

  static int _decimalPlaces(int scale) {
    var value = scale;
    var places = 0;
    while (value > 1 && value % 10 == 0) {
      value ~/= 10;
      places += 1;
    }
    if (value != 1) {
      throw ArgumentError.value(scale, 'scale', 'Scale must be a power of 10.');
    }
    return places;
  }
}
