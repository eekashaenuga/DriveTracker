import 'vehicle.dart';

class VehicleDraft {
  const VehicleDraft({
    required this.name,
    required this.make,
    required this.model,
    required this.fuelType,
    required this.distanceUnit,
    this.currentOdometer,
    this.year,
    this.registration,
    this.photoPath,
    this.trim,
    this.engine,
    this.transmission,
    this.vin,
    this.colour,
    this.purchaseDate,
    this.purchaseMileage,
    this.purchasePrice,
    this.seller,
    this.notes,
  });

  final String name;
  final String make;
  final String model;
  final int? currentOdometer;
  final FuelType fuelType;
  final DistanceUnit distanceUnit;
  final int? year;
  final String? registration;
  final String? photoPath;
  final String? trim;
  final String? engine;
  final String? transmission;
  final String? vin;
  final String? colour;
  final DateTime? purchaseDate;
  final int? purchaseMileage;
  final double? purchasePrice;
  final String? seller;
  final String? notes;
}
