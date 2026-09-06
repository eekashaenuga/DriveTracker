class ServiceItemDraft {
  const ServiceItemDraft({
    required this.itemName,
    this.maintenanceItemId,
    this.allocatedCostMinor,
    this.notes,
  });

  final String? maintenanceItemId;
  final String itemName;
  final int? allocatedCostMinor;
  final String? notes;
}

class ServiceRecordDraft {
  const ServiceRecordDraft({
    required this.vehicleId,
    required this.eventDateTime,
    required this.totalCostMinor,
    required this.items,
    this.odometer,
    this.garage,
    this.notes,
    this.isBaseline = false,
  });

  final String vehicleId;
  final DateTime eventDateTime;
  final int? odometer;
  final int totalCostMinor;
  final String? garage;
  final String? notes;
  final bool isBaseline;
  final List<ServiceItemDraft> items;
}

class ServiceRecord {
  const ServiceRecord({
    required this.id,
    required this.vehicleId,
    required this.eventDateTime,
    required this.totalCostMinor,
    required this.isBaseline,
    required this.createdAt,
    required this.updatedAt,
    this.odometer,
    this.garage,
    this.notes,
  });

  final String id;
  final String vehicleId;
  final DateTime eventDateTime;
  final int? odometer;
  final int totalCostMinor;
  final String? garage;
  final String? notes;
  final bool isBaseline;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'vehicle_id': vehicleId,
      'event_datetime': eventDateTime.toUtc().toIso8601String(),
      'odometer': odometer,
      'total_cost_minor': totalCostMinor,
      'garage': garage,
      'notes': notes,
      'is_baseline': isBaseline ? 1 : 0,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory ServiceRecord.fromMap(Map<String, Object?> map) {
    return ServiceRecord(
      id: map['id'] as String,
      vehicleId: map['vehicle_id'] as String,
      eventDateTime: DateTime.parse(map['event_datetime'] as String),
      odometer: map['odometer'] as int?,
      totalCostMinor: map['total_cost_minor'] as int,
      garage: map['garage'] as String?,
      notes: map['notes'] as String?,
      isBaseline: map['is_baseline'] == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

class ServiceItem {
  const ServiceItem({
    required this.id,
    required this.serviceId,
    required this.itemName,
    required this.createdAt,
    required this.updatedAt,
    this.maintenanceItemId,
    this.allocatedCostMinor,
    this.notes,
  });

  final String id;
  final String serviceId;
  final String? maintenanceItemId;
  final String itemName;
  final int? allocatedCostMinor;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'service_id': serviceId,
      'maintenance_item_id': maintenanceItemId,
      'item_name': itemName,
      'allocated_cost_minor': allocatedCostMinor,
      'notes': notes,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory ServiceItem.fromMap(Map<String, Object?> map) {
    return ServiceItem(
      id: map['id'] as String,
      serviceId: map['service_id'] as String,
      maintenanceItemId: map['maintenance_item_id'] as String?,
      itemName: map['item_name'] as String,
      allocatedCostMinor: map['allocated_cost_minor'] as int?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

class ServiceRecordWithItems {
  const ServiceRecordWithItems({required this.record, required this.items});

  final ServiceRecord record;
  final List<ServiceItem> items;
}

class MaintenanceCompletion {
  const MaintenanceCompletion({
    required this.serviceId,
    required this.serviceItemId,
    required this.maintenanceItemId,
    required this.itemName,
    required this.eventDateTime,
    required this.createdAt,
    required this.isBaseline,
    this.odometer,
    this.totalCostMinor,
    this.garage,
    this.notes,
  });

  final String serviceId;
  final String serviceItemId;
  final String maintenanceItemId;
  final String itemName;
  final DateTime eventDateTime;
  final DateTime createdAt;
  final int? odometer;
  final int? totalCostMinor;
  final String? garage;
  final String? notes;
  final bool isBaseline;
}
