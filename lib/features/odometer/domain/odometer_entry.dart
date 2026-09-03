enum OdometerSourceType {
  manual('Manual', 'MANUAL'),
  refuel('Refuel', 'REFUEL'),
  service('Service', 'SERVICE'),
  expense('Expense', 'EXPENSE'),
  other('Other', 'OTHER');

  const OdometerSourceType(this.label, this.storageValue);

  final String label;
  final String storageValue;

  static OdometerSourceType fromStorage(String value) {
    return OdometerSourceType.values.firstWhere(
      (sourceType) => sourceType.storageValue == value,
      orElse: () => OdometerSourceType.other,
    );
  }
}

class OdometerEntry {
  const OdometerEntry({
    required this.id,
    required this.vehicleId,
    required this.odometer,
    required this.eventDateTime,
    required this.sourceType,
    required this.createdAt,
    required this.updatedAt,
    this.sourceRecordId,
  });

  final String id;
  final String vehicleId;
  final int odometer;
  final DateTime eventDateTime;
  final OdometerSourceType sourceType;
  final String? sourceRecordId;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'vehicle_id': vehicleId,
      'odometer': odometer,
      'event_datetime': eventDateTime.toUtc().toIso8601String(),
      'source_type': sourceType.storageValue,
      'source_record_id': sourceRecordId,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory OdometerEntry.fromMap(Map<String, Object?> map) {
    return OdometerEntry(
      id: map['id'] as String,
      vehicleId: map['vehicle_id'] as String,
      odometer: map['odometer'] as int,
      eventDateTime: DateTime.parse(map['event_datetime'] as String),
      sourceType: OdometerSourceType.fromStorage(map['source_type'] as String),
      sourceRecordId: map['source_record_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
