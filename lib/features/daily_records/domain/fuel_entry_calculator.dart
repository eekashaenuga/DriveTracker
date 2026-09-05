enum FuelEntryField { totalCost, volume, unitPrice }

class FuelEntryValues {
  const FuelEntryValues({
    this.totalCostMinor,
    this.volumeMillilitres,
    this.unitPriceMicrosPerLitre,
  });

  final int? totalCostMinor;
  final int? volumeMillilitres;
  final int? unitPriceMicrosPerLitre;

  FuelEntryValues copyWith({
    int? totalCostMinor,
    int? volumeMillilitres,
    int? unitPriceMicrosPerLitre,
    bool clearTotalCost = false,
    bool clearVolume = false,
    bool clearUnitPrice = false,
  }) {
    return FuelEntryValues(
      totalCostMinor: clearTotalCost
          ? null
          : totalCostMinor ?? this.totalCostMinor,
      volumeMillilitres: clearVolume
          ? null
          : volumeMillilitres ?? this.volumeMillilitres,
      unitPriceMicrosPerLitre: clearUnitPrice
          ? null
          : unitPriceMicrosPerLitre ?? this.unitPriceMicrosPerLitre,
    );
  }
}

class FuelCalculationResult {
  const FuelCalculationResult({
    required this.values,
    required this.calculatedField,
    required this.manualFields,
  });

  final FuelEntryValues values;
  final FuelEntryField? calculatedField;
  final List<FuelEntryField> manualFields;
}

class FuelEntryCalculator {
  const FuelEntryCalculator._();

  static const _minorScale = 100;
  static const _millilitresPerLitre = 1000;
  static const _microsPerMajorUnit = 1000000;
  static const _totalDivisor =
      _millilitresPerLitre * _microsPerMajorUnit ~/ _minorScale;

  static FuelCalculationResult update({
    required FuelEntryValues current,
    required List<FuelEntryField> manualFields,
    required FuelEntryField editedField,
    required int? editedValue,
  }) {
    var values = _withEditedValue(current, editedField, editedValue);
    var nextManual = [
      for (final field in manualFields)
        if (field != editedField && _fieldValue(values, field) != null) field,
      if (editedValue != null) editedField,
    ];

    while (nextManual.length > 2) {
      nextManual.removeAt(0);
    }

    if (nextManual.length != 2) {
      return FuelCalculationResult(
        values: values,
        calculatedField: null,
        manualFields: nextManual,
      );
    }

    final missing = FuelEntryField.values.firstWhere(
      (field) => !nextManual.contains(field),
    );
    final calculated = _calculate(values, missing);
    if (calculated == null || calculated <= 0) {
      values = _clear(values, missing);
      return FuelCalculationResult(
        values: values,
        calculatedField: null,
        manualFields: nextManual,
      );
    }

    values = _withEditedValue(values, missing, calculated);
    return FuelCalculationResult(
      values: values,
      calculatedField: missing,
      manualFields: nextManual,
    );
  }

  static int? calculateUnitPriceMicrosPerLitre({
    required int totalCostMinor,
    required int volumeMillilitres,
  }) {
    if (totalCostMinor <= 0 || volumeMillilitres <= 0) {
      return null;
    }
    return _roundDiv(totalCostMinor * _totalDivisor, volumeMillilitres);
  }

  static int? calculateTotalCostMinor({
    required int volumeMillilitres,
    required int unitPriceMicrosPerLitre,
  }) {
    if (volumeMillilitres <= 0 || unitPriceMicrosPerLitre <= 0) {
      return null;
    }
    return _roundDiv(
      volumeMillilitres * unitPriceMicrosPerLitre,
      _totalDivisor,
    );
  }

  static int? calculateVolumeMillilitres({
    required int totalCostMinor,
    required int unitPriceMicrosPerLitre,
  }) {
    if (totalCostMinor <= 0 || unitPriceMicrosPerLitre <= 0) {
      return null;
    }
    return _roundDiv(totalCostMinor * _totalDivisor, unitPriceMicrosPerLitre);
  }

  static bool isConsistent(FuelEntryValues values, {int toleranceMinor = 1}) {
    final total = values.totalCostMinor;
    final volume = values.volumeMillilitres;
    final price = values.unitPriceMicrosPerLitre;
    if (total == null || volume == null || price == null) {
      return false;
    }
    if (total <= 0 || volume <= 0 || price <= 0) {
      return false;
    }

    final calculated = calculateTotalCostMinor(
      volumeMillilitres: volume,
      unitPriceMicrosPerLitre: price,
    );
    if (calculated == null) {
      return false;
    }
    return (calculated - total).abs() <= toleranceMinor;
  }

  static FuelEntryValues _withEditedValue(
    FuelEntryValues values,
    FuelEntryField field,
    int? value,
  ) {
    switch (field) {
      case FuelEntryField.totalCost:
        return values.copyWith(
          totalCostMinor: value,
          clearTotalCost: value == null,
        );
      case FuelEntryField.volume:
        return values.copyWith(
          volumeMillilitres: value,
          clearVolume: value == null,
        );
      case FuelEntryField.unitPrice:
        return values.copyWith(
          unitPriceMicrosPerLitre: value,
          clearUnitPrice: value == null,
        );
    }
  }

  static FuelEntryValues _clear(FuelEntryValues values, FuelEntryField field) {
    return _withEditedValue(values, field, null);
  }

  static int? _fieldValue(FuelEntryValues values, FuelEntryField field) {
    switch (field) {
      case FuelEntryField.totalCost:
        return values.totalCostMinor;
      case FuelEntryField.volume:
        return values.volumeMillilitres;
      case FuelEntryField.unitPrice:
        return values.unitPriceMicrosPerLitre;
    }
  }

  static int? _calculate(FuelEntryValues values, FuelEntryField missing) {
    switch (missing) {
      case FuelEntryField.totalCost:
        return calculateTotalCostMinor(
          volumeMillilitres: values.volumeMillilitres ?? 0,
          unitPriceMicrosPerLitre: values.unitPriceMicrosPerLitre ?? 0,
        );
      case FuelEntryField.volume:
        return calculateVolumeMillilitres(
          totalCostMinor: values.totalCostMinor ?? 0,
          unitPriceMicrosPerLitre: values.unitPriceMicrosPerLitre ?? 0,
        );
      case FuelEntryField.unitPrice:
        return calculateUnitPriceMicrosPerLitre(
          totalCostMinor: values.totalCostMinor ?? 0,
          volumeMillilitres: values.volumeMillilitres ?? 0,
        );
    }
  }

  static int _roundDiv(int numerator, int denominator) {
    return (numerator + denominator ~/ 2) ~/ denominator;
  }
}
