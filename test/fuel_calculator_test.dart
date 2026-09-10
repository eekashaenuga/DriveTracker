import 'package:drivetracker/features/calculator/domain/fuel_calculator.dart';
import 'package:drivetracker/features/daily_records/domain/refuel.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_services.dart';

void main() {
  group('Fuel unit conversions', () {
    test('converts miles and kilometres', () {
      expect(
        FuelUnitConversions.distanceToKilometers(10, DistanceUnit.miles),
        closeTo(16.09344, 0.00001),
      );
      expect(
        FuelUnitConversions.distanceFromKilometers(
          16.09344,
          DistanceUnit.miles,
        ),
        closeTo(10, 0.00001),
      );
      expect(
        FuelUnitConversions.distanceToKilometers(10, DistanceUnit.kilometers),
        10,
      );
    });

    test('converts litres, Imperial gallons and US gallons', () {
      expect(
        FuelUnitConversions.litresToVolume(
          4.54609,
          FuelVolumeUnit.imperialGallons,
        ),
        closeTo(1, 0.00001),
      );
      expect(
        FuelUnitConversions.volumeToLitres(1, FuelVolumeUnit.imperialGallons),
        closeTo(4.54609, 0.00001),
      );
      expect(
        FuelUnitConversions.volumeToLitres(1, FuelVolumeUnit.usGallons),
        closeTo(3.785411784, 0.000000001),
      );
    });

    test('converts reciprocal economy units correctly', () {
      expect(
        FuelUnitConversions.economyToLitresPer100Km(40, FuelEconomyUnit.ukMpg),
        closeTo(7.06202, 0.0001),
      );
      expect(
        FuelUnitConversions.economyToLitresPer100Km(40, FuelEconomyUnit.usMpg),
        closeTo(5.88036, 0.0001),
      );
      expect(
        FuelUnitConversions.economyToLitresPer100Km(
          20,
          FuelEconomyUnit.kilometersPerLitre,
        ),
        closeTo(5, 0.0001),
      );
      expect(
        FuelUnitConversions.convertEconomy(
          economy: 7.06155,
          from: FuelEconomyUnit.litresPer100Km,
          to: FuelEconomyUnit.ukMpg,
        ),
        closeTo(40, 0.01),
      );
      expect(
        FuelUnitConversions.economyToLitresPer100Km(0, FuelEconomyUnit.ukMpg),
        isNull,
      );
    });
  });

  group('Trip Cost', () {
    test('calculates UK MPG trip cost with miles and price per litre', () {
      final result = FuelCalculator.tripCost(
        const TripCostInput(
          distance: 100,
          distanceUnit: DistanceUnit.miles,
          fuelEconomy: 40,
          fuelEconomyUnit: FuelEconomyUnit.ukMpg,
          fuelPriceMicrosPerLitre: 1450000,
        ),
      );

      expect(result, isNotNull);
      expect(result!.fuelLitres, closeTo(11.365, 0.001));
      expect(result.estimatedCostMinor, 1648);
    });

    test('calculates US MPG trip cost without using Imperial gallons', () {
      final result = FuelCalculator.tripCost(
        const TripCostInput(
          distance: 100,
          distanceUnit: DistanceUnit.miles,
          fuelEconomy: 40,
          fuelEconomyUnit: FuelEconomyUnit.usMpg,
          fuelPriceMicrosPerLitre: 1450000,
        ),
      );

      expect(result, isNotNull);
      expect(result!.fuelLitres, closeTo(9.464, 0.001));
      expect(result.estimatedCostMinor, 1372);
    });

    test('calculates L/100 km and km/L trips with kilometre distances', () {
      final litresPer100Km = FuelCalculator.tripCost(
        const TripCostInput(
          distance: 160.9344,
          distanceUnit: DistanceUnit.kilometers,
          fuelEconomy: 7.06155,
          fuelEconomyUnit: FuelEconomyUnit.litresPer100Km,
          fuelPriceMicrosPerLitre: 1450000,
        ),
      );
      final kilometersPerLitre = FuelCalculator.tripCost(
        const TripCostInput(
          distance: 100,
          distanceUnit: DistanceUnit.kilometers,
          fuelEconomy: 20,
          fuelEconomyUnit: FuelEconomyUnit.kilometersPerLitre,
          fuelPriceMicrosPerLitre: 1450000,
        ),
      );

      expect(litresPer100Km!.fuelLitres, closeTo(11.365, 0.001));
      expect(kilometersPerLitre!.fuelLitres, closeTo(5, 0.001));
      expect(kilometersPerLitre.estimatedCostMinor, 725);
    });

    test('rejects zero or invalid trip values', () {
      expect(
        FuelCalculator.tripCost(
          const TripCostInput(
            distance: 0,
            distanceUnit: DistanceUnit.miles,
            fuelEconomy: 40,
            fuelEconomyUnit: FuelEconomyUnit.ukMpg,
            fuelPriceMicrosPerLitre: 1450000,
          ),
        ),
        isNull,
      );
      expect(
        FuelCalculator.fuelCostMinor(
          fuelLitres: 10,
          fuelPriceMicrosPerLitre: 0,
        ),
        isNull,
      );
    });
  });

  group('Fuel Required', () {
    test('calculates UK MPG fuel required and equivalent gallons', () {
      final result = FuelCalculator.fuelRequired(
        const FuelRequiredInput(
          distance: 400,
          distanceUnit: DistanceUnit.miles,
          fuelEconomy: 40,
          fuelEconomyUnit: FuelEconomyUnit.ukMpg,
        ),
      );

      expect(result, isNotNull);
      expect(result!.litres, closeTo(45.4609, 0.0001));
      expect(result.imperialGallons, closeTo(10, 0.0001));
      expect(result.usGallons, closeTo(12.0095, 0.0001));
    });

    test('supports US MPG, L/100 km and km/L fuel required', () {
      expect(
        FuelCalculator.fuelRequired(
          const FuelRequiredInput(
            distance: 100,
            distanceUnit: DistanceUnit.miles,
            fuelEconomy: 40,
            fuelEconomyUnit: FuelEconomyUnit.usMpg,
          ),
        )!.litres,
        closeTo(9.4635, 0.0001),
      );
      expect(
        FuelCalculator.fuelRequired(
          const FuelRequiredInput(
            distance: 100,
            distanceUnit: DistanceUnit.kilometers,
            fuelEconomy: 5,
            fuelEconomyUnit: FuelEconomyUnit.litresPer100Km,
          ),
        )!.litres,
        closeTo(5, 0.0001),
      );
      expect(
        FuelCalculator.fuelRequired(
          const FuelRequiredInput(
            distance: 100,
            distanceUnit: DistanceUnit.kilometers,
            fuelEconomy: 20,
            fuelEconomyUnit: FuelEconomyUnit.kilometersPerLitre,
          ),
        )!.litres,
        closeTo(5, 0.0001),
      );
    });
  });

  group('Cost Sharing', () {
    test('splits exact, one-person and non-even costs sensibly', () {
      expect(
        FuelCalculator.costSharing(
          const CostSharingInput.knownCost(totalCostMinor: 4200, people: 3),
        )!.costPerPersonMinor,
        1400,
      );
      expect(
        FuelCalculator.costSharing(
          const CostSharingInput.knownCost(totalCostMinor: 4200, people: 1),
        )!.costPerPersonMinor,
        4200,
      );
      expect(
        FuelCalculator.costSharing(
          const CostSharingInput.knownCost(totalCostMinor: 1000, people: 3),
        )!.costPerPersonMinor,
        333,
      );
    });

    test('uses estimated trip cost and rejects zero people', () {
      final result = FuelCalculator.costSharing(
        const CostSharingInput.estimatedTrip(
          trip: TripCostInput(
            distance: 100,
            distanceUnit: DistanceUnit.miles,
            fuelEconomy: 40,
            fuelEconomyUnit: FuelEconomyUnit.ukMpg,
            fuelPriceMicrosPerLitre: 1450000,
          ),
          people: 4,
        ),
      );

      expect(result!.totalCostMinor, 1648);
      expect(result.costPerPersonMinor, 412);
      expect(
        FuelCalculator.costSharing(
          const CostSharingInput.knownCost(totalCostMinor: 4200, people: 0),
        ),
        isNull,
      );
    });
  });

  group('Fuel Price Comparison', () {
    test('calculates gross saving and cheaper station', () {
      final result = FuelCalculator.priceComparison(
        const FuelPriceComparisonInput(
          fuelLitres: 50,
          stationAPriceMicrosPerLitre: 1450000,
          stationBPriceMicrosPerLitre: 1400000,
        ),
      );

      expect(result, isNotNull);
      expect(result!.stationACostMinor, 7250);
      expect(result.stationBCostMinor, 7000);
      expect(result.grossSavingMinor, 250);
      expect(result.betterOption, FuelPriceBetterOption.stationB);
      expect(result.netSavingMinor, isNull);
    });

    test('handles equal prices and station A being cheaper', () {
      expect(
        FuelCalculator.priceComparison(
          const FuelPriceComparisonInput(
            fuelLitres: 50,
            stationAPriceMicrosPerLitre: 1400000,
            stationBPriceMicrosPerLitre: 1400000,
          ),
        )!.betterOption,
        FuelPriceBetterOption.equal,
      );
      expect(
        FuelCalculator.priceComparison(
          const FuelPriceComparisonInput(
            fuelLitres: 50,
            stationAPriceMicrosPerLitre: 1390000,
            stationBPriceMicrosPerLitre: 1450000,
          ),
        )!.betterOption,
        FuelPriceBetterOption.stationA,
      );
    });

    test('calculates extra round-trip travel cost and net saving', () {
      final result = FuelCalculator.priceComparison(
        const FuelPriceComparisonInput(
          fuelLitres: 50,
          stationAPriceMicrosPerLitre: 1450000,
          stationBPriceMicrosPerLitre: 1400000,
          additionalRoundTripDistance: 10,
          additionalDistanceUnit: DistanceUnit.miles,
          fuelEconomy: 40,
          fuelEconomyUnit: FuelEconomyUnit.ukMpg,
        ),
      );

      expect(result, isNotNull);
      expect(result!.extraTravelLitres, closeTo(1.1365, 0.0001));
      expect(result.extraTravelCostMinor, 159);
      expect(result.netSavingMinor, 91);
    });

    test('reports near zero and negative net savings', () {
      final nearZero = FuelCalculator.priceComparison(
        const FuelPriceComparisonInput(
          fuelLitres: 31.8,
          stationAPriceMicrosPerLitre: 1450000,
          stationBPriceMicrosPerLitre: 1400000,
          additionalRoundTripDistance: 10,
          additionalDistanceUnit: DistanceUnit.miles,
          fuelEconomy: 40,
          fuelEconomyUnit: FuelEconomyUnit.ukMpg,
        ),
      );
      final negative = FuelCalculator.priceComparison(
        const FuelPriceComparisonInput(
          fuelLitres: 10,
          stationAPriceMicrosPerLitre: 1450000,
          stationBPriceMicrosPerLitre: 1400000,
          additionalRoundTripDistance: 10,
          additionalDistanceUnit: DistanceUnit.miles,
          fuelEconomy: 40,
          fuelEconomyUnit: FuelEconomyUnit.ukMpg,
        ),
      );

      expect(nearZero!.netSavingMinor, 0);
      expect(negative!.netSavingMinor, lessThan(0));
    });
  });

  group('Vehicle defaults', () {
    test(
      'valid full-to-full economy and latest fuel price can populate defaults',
      () async {
        final services = createTestServices();
        final vehicle = await services.vehicleService.addVehicle(
          _vehicleDraft('Commuter', 1000),
        );
        await services.refuelService.createRefuel(
          _refuelDraft(
            vehicle.id,
            odometer: 1000,
            eventDateTime: DateTime.utc(2026, 9, 1, 8),
            totalCostMinor: 4800,
            unitPriceMicrosPerLitre: 1200000,
          ),
        );
        await services.refuelService.createRefuel(
          _refuelDraft(
            vehicle.id,
            odometer: 1200,
            eventDateTime: DateTime.utc(2026, 9, 5, 8),
            totalCostMinor: 1200,
            volumeMillilitres: 8000,
            isFullTank: false,
            unitPriceMicrosPerLitre: 1500000,
          ),
        );
        await services.refuelService.createRefuel(
          _refuelDraft(
            vehicle.id,
            odometer: 1400,
            eventDateTime: DateTime.utc(2026, 9, 10, 8),
            totalCostMinor: 4480,
            volumeMillilitres: 32000,
            unitPriceMicrosPerLitre: 1400000,
          ),
        );

        final dashboard = await services.homeRepository.getVehicleDashboard(
          vehicle.id,
          now: DateTime.utc(2026, 9, 20, 12),
        );
        final defaults = VehicleFuelDefaults.fromDashboard(
          vehicle: dashboard.vehicle,
          latestFuelEconomyInterval: dashboard.latestFuelEconomyInterval,
          latestFuelPriceMicrosPerLitre:
              dashboard.latestFuelPriceMicrosPerLitre,
        );

        expect(defaults.trustedUkMpg, closeTo(45.46, 0.01));
        expect(defaults.latestFuelPriceMicrosPerLitre, 1400000);
        expect(defaults.distanceUnit, DistanceUnit.miles);
      },
    );

    test('partial or missed-history data does not fabricate economy', () async {
      final services = createTestServices();
      final vehicle = await services.vehicleService.addVehicle(
        _vehicleDraft('Commuter', 1000),
      );
      await services.refuelService.createRefuel(
        _refuelDraft(
          vehicle.id,
          odometer: 1000,
          eventDateTime: DateTime.utc(2026, 9, 1, 8),
        ),
      );
      await services.refuelService.createRefuel(
        _refuelDraft(
          vehicle.id,
          odometer: 1400,
          eventDateTime: DateTime.utc(2026, 9, 10, 8),
          missedPreviousRefuel: true,
        ),
      );

      final dashboard = await services.homeRepository.getVehicleDashboard(
        vehicle.id,
        now: DateTime.utc(2026, 9, 20, 12),
      );
      final defaults = VehicleFuelDefaults.fromDashboard(
        vehicle: dashboard.vehicle,
        latestFuelEconomyInterval: dashboard.latestFuelEconomyInterval,
        latestFuelPriceMicrosPerLitre: dashboard.latestFuelPriceMicrosPerLitre,
      );

      expect(defaults.trustedUkMpg, isNull);
      expect(defaults.latestFuelPriceMicrosPerLitre, 1250000);
    });

    test('vehicle defaults remain isolated per vehicle', () async {
      final services = createTestServices();
      final first = await services.vehicleService.addVehicle(
        _vehicleDraft('Commuter', 1000),
      );
      final second = await services.vehicleService.addVehicle(
        _vehicleDraft('Weekend', 5000),
      );
      await services.refuelService.createRefuel(
        _refuelDraft(
          first.id,
          odometer: 1000,
          eventDateTime: DateTime.utc(2026, 9, 1, 8),
          totalCostMinor: 4800,
          unitPriceMicrosPerLitre: 1200000,
        ),
      );
      await services.refuelService.createRefuel(
        _refuelDraft(
          first.id,
          odometer: 1400,
          eventDateTime: DateTime.utc(2026, 9, 10, 8),
          totalCostMinor: 5200,
          unitPriceMicrosPerLitre: 1300000,
        ),
      );
      await services.refuelService.createRefuel(
        _refuelDraft(
          second.id,
          odometer: 5100,
          eventDateTime: DateTime.utc(2026, 9, 11, 8),
          totalCostMinor: 6400,
          unitPriceMicrosPerLitre: 1600000,
        ),
      );

      final firstDashboard = await services.homeRepository.getVehicleDashboard(
        first.id,
        now: DateTime.utc(2026, 9, 20, 12),
      );
      final secondDashboard = await services.homeRepository.getVehicleDashboard(
        second.id,
        now: DateTime.utc(2026, 9, 20, 12),
      );

      final firstDefaults = VehicleFuelDefaults.fromDashboard(
        vehicle: firstDashboard.vehicle,
        latestFuelEconomyInterval: firstDashboard.latestFuelEconomyInterval,
        latestFuelPriceMicrosPerLitre:
            firstDashboard.latestFuelPriceMicrosPerLitre,
      );
      final secondDefaults = VehicleFuelDefaults.fromDashboard(
        vehicle: secondDashboard.vehicle,
        latestFuelEconomyInterval: secondDashboard.latestFuelEconomyInterval,
        latestFuelPriceMicrosPerLitre:
            secondDashboard.latestFuelPriceMicrosPerLitre,
      );

      expect(firstDefaults.latestFuelPriceMicrosPerLitre, 1300000);
      expect(firstDefaults.trustedUkMpg, isNotNull);
      expect(secondDefaults.latestFuelPriceMicrosPerLitre, 1600000);
      expect(secondDefaults.trustedUkMpg, isNull);
    });
  });
}

VehicleDraft _vehicleDraft(String name, int odometer) {
  return VehicleDraft(
    name: name,
    make: 'Ford',
    model: 'Focus',
    currentOdometer: odometer,
    fuelType: FuelType.petrol,
    distanceUnit: DistanceUnit.miles,
  );
}

RefuelDraft _refuelDraft(
  String vehicleId, {
  required int odometer,
  required DateTime eventDateTime,
  int totalCostMinor = 5000,
  int volumeMillilitres = 40000,
  int unitPriceMicrosPerLitre = 1250000,
  bool isFullTank = true,
  bool missedPreviousRefuel = false,
}) {
  return RefuelDraft(
    vehicleId: vehicleId,
    eventDateTime: eventDateTime,
    odometer: odometer,
    fuelType: FuelType.petrol,
    totalCostMinor: totalCostMinor,
    volumeMillilitres: volumeMillilitres,
    unitPriceMicrosPerLitre: unitPriceMicrosPerLitre,
    isFullTank: isFullTank,
    missedPreviousRefuel: missedPreviousRefuel,
  );
}
