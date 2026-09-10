import '../../../core/utilities/money.dart';
import '../../daily_records/domain/fuel_economy_calculator.dart';
import '../../vehicles/domain/vehicle.dart';

enum FuelEconomyUnit {
  ukMpg('UK MPG'),
  usMpg('US MPG'),
  litresPer100Km('L/100 km'),
  kilometersPerLitre('km/L');

  const FuelEconomyUnit(this.label);

  final String label;
}

enum FuelVolumeUnit {
  litres('Litres', 'L'),
  imperialGallons('Imperial gallons', 'imp gal'),
  usGallons('US gallons', 'US gal');

  const FuelVolumeUnit(this.label, this.shortLabel);

  final String label;
  final String shortLabel;
}

enum FuelPriceBetterOption { stationA, stationB, equal }

class FuelUnitConversions {
  const FuelUnitConversions._();

  static const kilometersPerMile = 1.609344;
  static const litresPerImperialGallon = 4.54609;
  static const litresPerUsGallon = 3.785411784;
  static const imperialGallonsPerLitre = 1 / litresPerImperialGallon;
  static const usGallonsPerLitre = 1 / litresPerUsGallon;

  static double? distanceToKilometers(double distance, DistanceUnit unit) {
    if (!_positive(distance)) {
      return null;
    }
    return switch (unit) {
      DistanceUnit.miles => distance * kilometersPerMile,
      DistanceUnit.kilometers => distance,
    };
  }

  static double? distanceFromKilometers(double kilometers, DistanceUnit unit) {
    if (!_positive(kilometers)) {
      return null;
    }
    return switch (unit) {
      DistanceUnit.miles => kilometers / kilometersPerMile,
      DistanceUnit.kilometers => kilometers,
    };
  }

  static double? litresToVolume(double litres, FuelVolumeUnit unit) {
    if (!_positive(litres)) {
      return null;
    }
    return switch (unit) {
      FuelVolumeUnit.litres => litres,
      FuelVolumeUnit.imperialGallons => litres / litresPerImperialGallon,
      FuelVolumeUnit.usGallons => litres / litresPerUsGallon,
    };
  }

  static double? volumeToLitres(double volume, FuelVolumeUnit unit) {
    if (!_positive(volume)) {
      return null;
    }
    return switch (unit) {
      FuelVolumeUnit.litres => volume,
      FuelVolumeUnit.imperialGallons => volume * litresPerImperialGallon,
      FuelVolumeUnit.usGallons => volume * litresPerUsGallon,
    };
  }

  static double? economyToLitresPer100Km(double economy, FuelEconomyUnit unit) {
    if (!_positive(economy)) {
      return null;
    }
    return switch (unit) {
      FuelEconomyUnit.ukMpg =>
        litresPerImperialGallon * 100 / (economy * kilometersPerMile),
      FuelEconomyUnit.usMpg =>
        litresPerUsGallon * 100 / (economy * kilometersPerMile),
      FuelEconomyUnit.litresPer100Km => economy,
      FuelEconomyUnit.kilometersPerLitre => 100 / economy,
    };
  }

  static double? economyFromLitresPer100Km(
    double litresPer100Km,
    FuelEconomyUnit unit,
  ) {
    if (!_positive(litresPer100Km)) {
      return null;
    }
    return switch (unit) {
      FuelEconomyUnit.ukMpg =>
        litresPerImperialGallon * 100 / (litresPer100Km * kilometersPerMile),
      FuelEconomyUnit.usMpg =>
        litresPerUsGallon * 100 / (litresPer100Km * kilometersPerMile),
      FuelEconomyUnit.litresPer100Km => litresPer100Km,
      FuelEconomyUnit.kilometersPerLitre => 100 / litresPer100Km,
    };
  }

  static double? convertEconomy({
    required double economy,
    required FuelEconomyUnit from,
    required FuelEconomyUnit to,
  }) {
    final litresPer100Km = economyToLitresPer100Km(economy, from);
    if (litresPer100Km == null) {
      return null;
    }
    return economyFromLitresPer100Km(litresPer100Km, to);
  }

  static bool _positive(double value) {
    return value > 0 && value.isFinite;
  }
}

class TripCostInput {
  const TripCostInput({
    required this.distance,
    required this.distanceUnit,
    required this.fuelEconomy,
    required this.fuelEconomyUnit,
    required this.fuelPriceMicrosPerLitre,
  });

  final double distance;
  final DistanceUnit distanceUnit;
  final double fuelEconomy;
  final FuelEconomyUnit fuelEconomyUnit;
  final int fuelPriceMicrosPerLitre;
}

class TripCostResult {
  const TripCostResult({
    required this.fuelLitres,
    required this.estimatedCostMinor,
    required this.costMinorPerDistance,
  });

  final double fuelLitres;
  final int estimatedCostMinor;
  final double costMinorPerDistance;
}

class FuelRequiredInput {
  const FuelRequiredInput({
    required this.distance,
    required this.distanceUnit,
    required this.fuelEconomy,
    required this.fuelEconomyUnit,
  });

  final double distance;
  final DistanceUnit distanceUnit;
  final double fuelEconomy;
  final FuelEconomyUnit fuelEconomyUnit;
}

class FuelRequiredResult {
  const FuelRequiredResult({
    required this.litres,
    required this.imperialGallons,
    required this.usGallons,
  });

  final double litres;
  final double imperialGallons;
  final double usGallons;
}

class CostSharingInput {
  const CostSharingInput.estimatedTrip({
    required TripCostInput trip,
    required this.people,
  }) : tripCostInput = trip,
       knownTotalCostMinor = null;

  const CostSharingInput.knownCost({
    required int totalCostMinor,
    required this.people,
  }) : knownTotalCostMinor = totalCostMinor,
       tripCostInput = null;

  final TripCostInput? tripCostInput;
  final int? knownTotalCostMinor;
  final int people;
}

class CostSharingResult {
  const CostSharingResult({
    required this.totalCostMinor,
    required this.costPerPersonMinor,
  });

  final int totalCostMinor;
  final int costPerPersonMinor;
}

class FuelPriceComparisonInput {
  const FuelPriceComparisonInput({
    required this.fuelLitres,
    required this.stationAPriceMicrosPerLitre,
    required this.stationBPriceMicrosPerLitre,
    this.additionalRoundTripDistance,
    this.additionalDistanceUnit,
    this.fuelEconomy,
    this.fuelEconomyUnit,
  });

  final double fuelLitres;
  final int stationAPriceMicrosPerLitre;
  final int stationBPriceMicrosPerLitre;
  final double? additionalRoundTripDistance;
  final DistanceUnit? additionalDistanceUnit;
  final double? fuelEconomy;
  final FuelEconomyUnit? fuelEconomyUnit;
}

class FuelPriceComparisonResult {
  const FuelPriceComparisonResult({
    required this.stationACostMinor,
    required this.stationBCostMinor,
    required this.grossSavingMinor,
    required this.betterOption,
    this.extraTravelLitres,
    this.extraTravelCostMinor,
    this.netSavingMinor,
  });

  final int stationACostMinor;
  final int stationBCostMinor;
  final int grossSavingMinor;
  final FuelPriceBetterOption betterOption;
  final double? extraTravelLitres;
  final int? extraTravelCostMinor;
  final int? netSavingMinor;

  bool get hasTravelAdjustment {
    return extraTravelLitres != null &&
        extraTravelCostMinor != null &&
        netSavingMinor != null;
  }
}

class VehicleFuelDefaults {
  const VehicleFuelDefaults({
    required this.vehicle,
    required this.distanceUnit,
    required this.trustedUkMpg,
    required this.latestFuelPriceMicrosPerLitre,
  });

  factory VehicleFuelDefaults.fromDashboard({
    required Vehicle? vehicle,
    required FuelEconomyInterval? latestFuelEconomyInterval,
    required int? latestFuelPriceMicrosPerLitre,
  }) {
    final ukMpg = latestFuelEconomyInterval?.ukMpg;
    return VehicleFuelDefaults(
      vehicle: vehicle,
      distanceUnit: vehicle?.distanceUnit,
      trustedUkMpg: ukMpg != null && ukMpg > 0 && ukMpg.isFinite ? ukMpg : null,
      latestFuelPriceMicrosPerLitre:
          latestFuelPriceMicrosPerLitre != null &&
              latestFuelPriceMicrosPerLitre > 0
          ? latestFuelPriceMicrosPerLitre
          : null,
    );
  }

  final Vehicle? vehicle;
  final DistanceUnit? distanceUnit;
  final double? trustedUkMpg;
  final int? latestFuelPriceMicrosPerLitre;

  bool get hasTrustedEconomy => trustedUkMpg != null;
  bool get hasLatestFuelPrice => latestFuelPriceMicrosPerLitre != null;
  bool get hasAnyVehicleDefault => hasTrustedEconomy || hasLatestFuelPrice;
}

class FuelCalculator {
  const FuelCalculator._();

  static FuelRequiredResult? fuelRequired(FuelRequiredInput input) {
    final litres = fuelLitresRequired(
      distance: input.distance,
      distanceUnit: input.distanceUnit,
      fuelEconomy: input.fuelEconomy,
      fuelEconomyUnit: input.fuelEconomyUnit,
    );
    if (litres == null) {
      return null;
    }
    return FuelRequiredResult(
      litres: litres,
      imperialGallons: FuelUnitConversions.litresToVolume(
        litres,
        FuelVolumeUnit.imperialGallons,
      )!,
      usGallons: FuelUnitConversions.litresToVolume(
        litres,
        FuelVolumeUnit.usGallons,
      )!,
    );
  }

  static TripCostResult? tripCost(TripCostInput input) {
    final requiredFuel = fuelLitresRequired(
      distance: input.distance,
      distanceUnit: input.distanceUnit,
      fuelEconomy: input.fuelEconomy,
      fuelEconomyUnit: input.fuelEconomyUnit,
    );
    final costMinor = requiredFuel == null
        ? null
        : fuelCostMinor(
            fuelLitres: requiredFuel,
            fuelPriceMicrosPerLitre: input.fuelPriceMicrosPerLitre,
          );
    if (requiredFuel == null || costMinor == null || input.distance <= 0) {
      return null;
    }
    return TripCostResult(
      fuelLitres: requiredFuel,
      estimatedCostMinor: costMinor,
      costMinorPerDistance: costMinor / input.distance,
    );
  }

  static CostSharingResult? costSharing(CostSharingInput input) {
    if (input.people < 1) {
      return null;
    }

    final knownCost = input.knownTotalCostMinor;
    final trip = input.tripCostInput;
    final totalCost =
        knownCost ?? (trip == null ? null : tripCost(trip)?.estimatedCostMinor);
    if (totalCost == null || totalCost <= 0) {
      return null;
    }

    return CostSharingResult(
      totalCostMinor: totalCost,
      costPerPersonMinor: (totalCost / input.people).round(),
    );
  }

  static FuelPriceComparisonResult? priceComparison(
    FuelPriceComparisonInput input,
  ) {
    final stationACost = fuelCostMinor(
      fuelLitres: input.fuelLitres,
      fuelPriceMicrosPerLitre: input.stationAPriceMicrosPerLitre,
    );
    final stationBCost = fuelCostMinor(
      fuelLitres: input.fuelLitres,
      fuelPriceMicrosPerLitre: input.stationBPriceMicrosPerLitre,
    );
    if (stationACost == null || stationBCost == null) {
      return null;
    }

    final betterOption = stationACost == stationBCost
        ? FuelPriceBetterOption.equal
        : stationACost < stationBCost
        ? FuelPriceBetterOption.stationA
        : FuelPriceBetterOption.stationB;
    final grossSaving = (stationACost - stationBCost).abs();

    final extraFuelLitres = _extraTravelFuelLitres(input);
    final cheaperPrice = betterOption == FuelPriceBetterOption.stationA
        ? input.stationAPriceMicrosPerLitre
        : input.stationBPriceMicrosPerLitre;
    final extraTravelCost =
        betterOption == FuelPriceBetterOption.equal || extraFuelLitres == null
        ? null
        : fuelCostMinor(
            fuelLitres: extraFuelLitres,
            fuelPriceMicrosPerLitre: cheaperPrice,
          );

    return FuelPriceComparisonResult(
      stationACostMinor: stationACost,
      stationBCostMinor: stationBCost,
      grossSavingMinor: grossSaving,
      betterOption: betterOption,
      extraTravelLitres: extraTravelCost == null ? null : extraFuelLitres,
      extraTravelCostMinor: extraTravelCost,
      netSavingMinor: extraTravelCost == null
          ? null
          : grossSaving - extraTravelCost,
    );
  }

  static double? fuelLitresRequired({
    required double distance,
    required DistanceUnit distanceUnit,
    required double fuelEconomy,
    required FuelEconomyUnit fuelEconomyUnit,
  }) {
    final kilometers = FuelUnitConversions.distanceToKilometers(
      distance,
      distanceUnit,
    );
    final litresPer100Km = FuelUnitConversions.economyToLitresPer100Km(
      fuelEconomy,
      fuelEconomyUnit,
    );
    if (kilometers == null || litresPer100Km == null) {
      return null;
    }
    final litres = kilometers * litresPer100Km / 100;
    return litres > 0 && litres.isFinite ? litres : null;
  }

  static int? fuelCostMinor({
    required double fuelLitres,
    required int fuelPriceMicrosPerLitre,
    CurrencySpec currency = MoneyAmount.defaultCurrency,
  }) {
    if (fuelLitres <= 0 ||
        !fuelLitres.isFinite ||
        fuelPriceMicrosPerLitre <= 0) {
      return null;
    }
    final minor =
        fuelLitres *
        fuelPriceMicrosPerLitre *
        currency.minorScale /
        FuelNumbers.microsPerMajorUnit;
    if (!minor.isFinite || minor <= 0) {
      return null;
    }
    return minor.round();
  }

  static double? _extraTravelFuelLitres(FuelPriceComparisonInput input) {
    final distance = input.additionalRoundTripDistance;
    final distanceUnit = input.additionalDistanceUnit;
    final economy = input.fuelEconomy;
    final economyUnit = input.fuelEconomyUnit;
    if (distance == null ||
        distanceUnit == null ||
        economy == null ||
        economyUnit == null) {
      return null;
    }
    return fuelLitresRequired(
      distance: distance,
      distanceUnit: distanceUnit,
      fuelEconomy: economy,
      fuelEconomyUnit: economyUnit,
    );
  }
}
