enum FuelType {
  petrol('Petrol', 'PETROL'),
  diesel('Diesel', 'DIESEL'),
  hybrid('Hybrid', 'HYBRID'),
  electric('Electric', 'ELECTRIC'),
  lpg('LPG', 'LPG'),
  other('Other', 'OTHER');

  const FuelType(this.label, this.storageValue);

  final String label;
  final String storageValue;

  static FuelType fromStorage(String value) {
    return FuelType.values.firstWhere(
      (type) => type.storageValue == value,
      orElse: () => FuelType.other,
    );
  }
}

enum DistanceUnit {
  miles('Miles', 'mi', 'MILES'),
  kilometers('Kilometers', 'km', 'KILOMETERS');

  const DistanceUnit(this.label, this.shortLabel, this.storageValue);

  final String label;
  final String shortLabel;
  final String storageValue;

  static DistanceUnit fromStorage(String value) {
    return DistanceUnit.values.firstWhere(
      (unit) => unit.storageValue == value,
      orElse: () => DistanceUnit.miles,
    );
  }
}

class Vehicle {
  const Vehicle({
    required this.id,
    required this.name,
    required this.make,
    required this.model,
    required this.fuelType,
    required this.distanceUnit,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
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

  final String id;
  final String name;
  final String make;
  final String model;
  final int? year;
  final String? registration;
  final FuelType fuelType;
  final DistanceUnit distanceUnit;
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
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get description {
    final details = <String>[if (year != null) year.toString(), make, model];
    return details.join(' ');
  }

  String get registrationLabel {
    final value = registration;
    if (value == null || value.isEmpty) {
      return 'No registration';
    }
    return value;
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'make': make,
      'model': model,
      'year': year,
      'registration': registration,
      'fuel_type': fuelType.storageValue,
      'distance_unit': distanceUnit.storageValue,
      'photo_path': photoPath,
      'trim': trim,
      'engine': engine,
      'transmission': transmission,
      'vin': vin,
      'colour': colour,
      'purchase_date': purchaseDate?.toUtc().toIso8601String(),
      'purchase_mileage': purchaseMileage,
      'purchase_price': purchasePrice,
      'seller': seller,
      'notes': notes,
      'is_archived': isArchived ? 1 : 0,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory Vehicle.fromMap(Map<String, Object?> map) {
    return Vehicle(
      id: map['id'] as String,
      name: map['name'] as String,
      make: map['make'] as String,
      model: map['model'] as String,
      year: map['year'] as int?,
      registration: map['registration'] as String?,
      fuelType: FuelType.fromStorage(map['fuel_type'] as String),
      distanceUnit: DistanceUnit.fromStorage(map['distance_unit'] as String),
      photoPath: map['photo_path'] as String?,
      trim: map['trim'] as String?,
      engine: map['engine'] as String?,
      transmission: map['transmission'] as String?,
      vin: map['vin'] as String?,
      colour: map['colour'] as String?,
      purchaseDate: _optionalDate(map['purchase_date']),
      purchaseMileage: map['purchase_mileage'] as int?,
      purchasePrice: (map['purchase_price'] as num?)?.toDouble(),
      seller: map['seller'] as String?,
      notes: map['notes'] as String?,
      isArchived: map['is_archived'] == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  static DateTime? _optionalDate(Object? value) {
    if (value == null) {
      return null;
    }
    return DateTime.parse(value as String);
  }
}
