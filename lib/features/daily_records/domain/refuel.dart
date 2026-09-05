import '../../vehicles/domain/vehicle.dart';

class RefuelDraft {
  const RefuelDraft({
    required this.vehicleId,
    required this.eventDateTime,
    required this.odometer,
    required this.fuelType,
    required this.totalCostMinor,
    required this.volumeMillilitres,
    required this.unitPriceMicrosPerLitre,
    required this.isFullTank,
    required this.missedPreviousRefuel,
    this.station,
    this.notes,
  });

  final String vehicleId;
  final DateTime eventDateTime;
  final int odometer;
  final FuelType fuelType;
  final int totalCostMinor;
  final int volumeMillilitres;
  final int unitPriceMicrosPerLitre;
  final bool isFullTank;
  final bool missedPreviousRefuel;
  final String? station;
  final String? notes;
}

class Refuel {
  const Refuel({
    required this.id,
    required this.vehicleId,
    required this.eventDateTime,
    required this.odometer,
    required this.fuelType,
    required this.totalCostMinor,
    required this.volumeMillilitres,
    required this.unitPriceMicrosPerLitre,
    required this.isFullTank,
    required this.missedPreviousRefuel,
    required this.createdAt,
    required this.updatedAt,
    this.station,
    this.notes,
  });

  final String id;
  final String vehicleId;
  final DateTime eventDateTime;
  final int odometer;
  final FuelType fuelType;
  final int totalCostMinor;
  final int volumeMillilitres;
  final int unitPriceMicrosPerLitre;
  final bool isFullTank;
  final bool missedPreviousRefuel;
  final String? station;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'vehicle_id': vehicleId,
      'event_datetime': eventDateTime.toUtc().toIso8601String(),
      'odometer': odometer,
      'fuel_type': fuelType.storageValue,
      'total_cost_minor': totalCostMinor,
      'volume_millilitres': volumeMillilitres,
      'unit_price_micros_per_litre': unitPriceMicrosPerLitre,
      'is_full_tank': isFullTank ? 1 : 0,
      'missed_previous_refuel': missedPreviousRefuel ? 1 : 0,
      'station': station,
      'notes': notes,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory Refuel.fromMap(Map<String, Object?> map) {
    return Refuel(
      id: map['id'] as String,
      vehicleId: map['vehicle_id'] as String,
      eventDateTime: DateTime.parse(map['event_datetime'] as String),
      odometer: map['odometer'] as int,
      fuelType: FuelType.fromStorage(map['fuel_type'] as String),
      totalCostMinor: map['total_cost_minor'] as int,
      volumeMillilitres: map['volume_millilitres'] as int,
      unitPriceMicrosPerLitre: map['unit_price_micros_per_litre'] as int,
      isFullTank: map['is_full_tank'] == 1,
      missedPreviousRefuel: map['missed_previous_refuel'] == 1,
      station: map['station'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
