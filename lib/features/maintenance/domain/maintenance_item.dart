class MaintenanceItemDraft {
  const MaintenanceItemDraft({
    required this.vehicleId,
    required this.name,
    this.category,
    this.mileageInterval,
    this.timeIntervalDays,
    this.mileageWarning = 1000,
    this.dateWarningDays = 30,
    this.reminderEnabled = true,
  });

  final String vehicleId;
  final String name;
  final String? category;
  final int? mileageInterval;
  final int? timeIntervalDays;
  final int mileageWarning;
  final int dateWarningDays;
  final bool reminderEnabled;
}

class MaintenanceItem {
  const MaintenanceItem({
    required this.id,
    required this.vehicleId,
    required this.name,
    required this.mileageWarning,
    required this.dateWarningDays,
    required this.reminderEnabled,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
    this.category,
    this.mileageInterval,
    this.timeIntervalDays,
  });

  final String id;
  final String vehicleId;
  final String name;
  final String? category;
  final int? mileageInterval;
  final int? timeIntervalDays;
  final int mileageWarning;
  final int dateWarningDays;
  final bool reminderEnabled;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasInterval => mileageInterval != null || timeIntervalDays != null;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'vehicle_id': vehicleId,
      'name': name,
      'category': category,
      'mileage_interval': mileageInterval,
      'time_interval_days': timeIntervalDays,
      'mileage_warning': mileageWarning,
      'date_warning_days': dateWarningDays,
      'reminder_enabled': reminderEnabled ? 1 : 0,
      'is_archived': isArchived ? 1 : 0,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory MaintenanceItem.fromMap(Map<String, Object?> map) {
    return MaintenanceItem(
      id: map['id'] as String,
      vehicleId: map['vehicle_id'] as String,
      name: map['name'] as String,
      category: map['category'] as String?,
      mileageInterval: map['mileage_interval'] as int?,
      timeIntervalDays: map['time_interval_days'] as int?,
      mileageWarning: map['mileage_warning'] as int,
      dateWarningDays: map['date_warning_days'] as int,
      reminderEnabled: map['reminder_enabled'] == 1,
      isArchived: map['is_archived'] == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
