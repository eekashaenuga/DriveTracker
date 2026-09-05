import '../../../core/utilities/money.dart';
import '../../vehicles/domain/vehicle.dart';
import 'refuel.dart';

class FuelEconomyInterval {
  const FuelEconomyInterval({
    required this.startRefuel,
    required this.endRefuel,
    required this.distance,
    required this.volumeMillilitres,
    required this.ukMpg,
  });

  final Refuel startRefuel;
  final Refuel endRefuel;
  final int distance;
  final int volumeMillilitres;
  final double ukMpg;
}

class FuelEconomyCalculator {
  const FuelEconomyCalculator._();

  static List<FuelEconomyInterval> validIntervals({
    required List<Refuel> refuels,
    required DistanceUnit distanceUnit,
  }) {
    final sorted = [...refuels]
      ..sort((a, b) {
        final eventCompare = a.eventDateTime.compareTo(b.eventDateTime);
        if (eventCompare != 0) {
          return eventCompare;
        }
        return a.createdAt.compareTo(b.createdAt);
      });

    Refuel? startFull;
    var accumulatedMillilitres = 0;
    final intervals = <FuelEconomyInterval>[];

    for (final refuel in sorted) {
      if (refuel.missedPreviousRefuel) {
        startFull = refuel.isFullTank ? refuel : null;
        accumulatedMillilitres = 0;
        continue;
      }

      final start = startFull;
      if (start == null) {
        if (refuel.isFullTank) {
          startFull = refuel;
          accumulatedMillilitres = 0;
        }
        continue;
      }

      if (refuel.odometer <= start.odometer) {
        startFull = refuel.isFullTank ? refuel : null;
        accumulatedMillilitres = 0;
        continue;
      }

      accumulatedMillilitres += refuel.volumeMillilitres;
      if (!refuel.isFullTank) {
        continue;
      }

      final distance = refuel.odometer - start.odometer;
      final ukMpg = _ukMpg(
        distance: distance,
        volumeMillilitres: accumulatedMillilitres,
        distanceUnit: distanceUnit,
      );
      if (ukMpg != null) {
        intervals.add(
          FuelEconomyInterval(
            startRefuel: start,
            endRefuel: refuel,
            distance: distance,
            volumeMillilitres: accumulatedMillilitres,
            ukMpg: ukMpg,
          ),
        );
      }

      startFull = refuel;
      accumulatedMillilitres = 0;
    }

    return intervals;
  }

  static FuelEconomyInterval? latestValidInterval({
    required List<Refuel> refuels,
    required DistanceUnit distanceUnit,
  }) {
    final intervals = validIntervals(
      refuels: refuels,
      distanceUnit: distanceUnit,
    );
    if (intervals.isEmpty) {
      return null;
    }
    return intervals.last;
  }

  static double? _ukMpg({
    required int distance,
    required int volumeMillilitres,
    required DistanceUnit distanceUnit,
  }) {
    if (distance <= 0 || volumeMillilitres <= 0) {
      return null;
    }
    if (distanceUnit != DistanceUnit.miles) {
      return null;
    }

    final litres = volumeMillilitres / FuelNumbers.millilitresPerLitre;
    final gallons = litres * FuelNumbers.imperialGallonsPerLitre;
    if (gallons <= 0) {
      return null;
    }
    return distance / gallons;
  }
}
