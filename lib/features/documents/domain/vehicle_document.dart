import '../../maintenance/domain/maintenance_reminder.dart';

const defaultDocumentCategories = [
  'Insurance',
  'MOT',
  'V5C',
  'Purchase receipt',
  'Warranty',
  'Breakdown cover',
  'Tax',
  'Finance / Lease',
  'Other',
];

enum DocumentStatus {
  noExpiry('No expiry'),
  valid('Recorded'),
  expiringSoon('Expiring soon'),
  expired('Expired');

  const DocumentStatus(this.label);

  final String label;

  int get severity {
    return switch (this) {
      DocumentStatus.noExpiry => 0,
      DocumentStatus.valid => 0,
      DocumentStatus.expiringSoon => 2,
      DocumentStatus.expired => 4,
    };
  }
}

class VehicleDocumentDraft {
  const VehicleDocumentDraft({
    required this.vehicleId,
    required this.category,
    required this.title,
    this.issueDate,
    this.expiryDate,
    this.referenceNumber,
    this.provider,
    this.notes,
  });

  final String vehicleId;
  final String category;
  final String title;
  final DateTime? issueDate;
  final DateTime? expiryDate;
  final String? referenceNumber;
  final String? provider;
  final String? notes;
}

class VehicleDocument {
  const VehicleDocument({
    required this.id,
    required this.vehicleId,
    required this.category,
    required this.title,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
    this.issueDate,
    this.expiryDate,
    this.referenceNumber,
    this.provider,
    this.notes,
    this.reminderId,
    this.archivedAt,
  });

  final String id;
  final String vehicleId;
  final String category;
  final String title;
  final DateTime? issueDate;
  final DateTime? expiryDate;
  final String? referenceNumber;
  final String? provider;
  final String? notes;
  final String? reminderId;
  final bool isArchived;
  final DateTime? archivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  int? daysUntilExpiry(DateTime asOf) {
    final expiry = expiryDate;
    if (expiry == null) {
      return null;
    }
    return _dateOnly(expiry).difference(_dateOnly(asOf)).inDays;
  }

  DocumentStatus statusAt(DateTime asOf) {
    final days = daysUntilExpiry(asOf);
    if (days == null) {
      return DocumentStatus.noExpiry;
    }
    if (days < 0) {
      return DocumentStatus.expired;
    }
    if (days <= DocumentExpiryReminder.expiringSoonDays) {
      return DocumentStatus.expiringSoon;
    }
    return DocumentStatus.valid;
  }

  VehicleDocument copyWith({
    String? category,
    String? title,
    DateTime? issueDate,
    DateTime? expiryDate,
    String? referenceNumber,
    String? provider,
    String? notes,
    bool? isArchived,
    DateTime? archivedAt,
    DateTime? updatedAt,
  }) {
    return VehicleDocument(
      id: id,
      vehicleId: vehicleId,
      category: category ?? this.category,
      title: title ?? this.title,
      issueDate: issueDate ?? this.issueDate,
      expiryDate: expiryDate ?? this.expiryDate,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      provider: provider ?? this.provider,
      notes: notes ?? this.notes,
      reminderId: reminderId,
      isArchived: isArchived ?? this.isArchived,
      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'vehicle_id': vehicleId,
      'category': category,
      'title': title,
      'issue_date': _dateToStorage(issueDate),
      'expiry_date': _dateToStorage(expiryDate),
      'reference_number': referenceNumber,
      'provider': provider,
      'notes': notes,
      'reminder_id': reminderId,
      'is_archived': isArchived ? 1 : 0,
      'archived_at': archivedAt?.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory VehicleDocument.fromMap(Map<String, Object?> map) {
    return VehicleDocument(
      id: map['id'] as String,
      vehicleId: map['vehicle_id'] as String,
      category: map['category'] as String,
      title: map['title'] as String,
      issueDate: _dateFromStorage(map['issue_date']),
      expiryDate: _dateFromStorage(map['expiry_date']),
      referenceNumber: map['reference_number'] as String?,
      provider: map['provider'] as String?,
      notes: map['notes'] as String?,
      reminderId: map['reminder_id'] as String?,
      isArchived: map['is_archived'] == 1,
      archivedAt: _dateTimeFromStorage(map['archived_at']),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

class DocumentExpiryReminder {
  const DocumentExpiryReminder({
    required this.document,
    required this.state,
    required this.daysRemaining,
  });

  static const expiringSoonDays = 30;

  final VehicleDocument document;
  final MaintenanceReminderState state;
  final int daysRemaining;

  bool get shouldShowAsReminder {
    return !document.isArchived &&
        state.severity >= MaintenanceReminderState.upcoming.severity;
  }

  String get id => 'document_${document.id}';

  String get title => '${document.category}: ${document.title}';

  factory DocumentExpiryReminder.evaluate({
    required VehicleDocument document,
    required DateTime asOf,
  }) {
    final days = document.daysUntilExpiry(asOf);
    if (document.isArchived || days == null) {
      return DocumentExpiryReminder(
        document: document,
        state: MaintenanceReminderState.normal,
        daysRemaining: days ?? 1 << 30,
      );
    }
    final state = switch (days) {
      < 0 => MaintenanceReminderState.overdue,
      0 => MaintenanceReminderState.due,
      <= 7 => MaintenanceReminderState.dueSoon,
      <= expiringSoonDays => MaintenanceReminderState.upcoming,
      _ => MaintenanceReminderState.normal,
    };
    return DocumentExpiryReminder(
      document: document,
      state: state,
      daysRemaining: days,
    );
  }
}

DateTime _dateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

String? _dateToStorage(DateTime? value) {
  if (value == null) {
    return null;
  }
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

DateTime? _dateFromStorage(Object? value) {
  if (value == null) {
    return null;
  }
  final parts = (value as String).split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

DateTime? _dateTimeFromStorage(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.parse(value as String);
}
