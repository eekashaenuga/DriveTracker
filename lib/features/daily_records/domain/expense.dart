class ExpenseDraft {
  const ExpenseDraft({
    required this.vehicleId,
    required this.categoryId,
    required this.eventDateTime,
    required this.amountMinor,
    this.odometer,
    this.merchant,
    this.paymentMethod,
    this.notes,
  });

  final String vehicleId;
  final String categoryId;
  final DateTime eventDateTime;
  final int amountMinor;
  final int? odometer;
  final String? merchant;
  final String? paymentMethod;
  final String? notes;
}

class Expense {
  const Expense({
    required this.id,
    required this.vehicleId,
    required this.categoryId,
    required this.eventDateTime,
    required this.amountMinor,
    required this.createdAt,
    required this.updatedAt,
    this.odometer,
    this.merchant,
    this.paymentMethod,
    this.notes,
  });

  final String id;
  final String vehicleId;
  final String categoryId;
  final DateTime eventDateTime;
  final int? odometer;
  final int amountMinor;
  final String? merchant;
  final String? paymentMethod;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'vehicle_id': vehicleId,
      'category_id': categoryId,
      'event_datetime': eventDateTime.toUtc().toIso8601String(),
      'odometer': odometer,
      'amount_minor': amountMinor,
      'merchant': merchant,
      'payment_method': paymentMethod,
      'notes': notes,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory Expense.fromMap(Map<String, Object?> map) {
    return Expense(
      id: map['id'] as String,
      vehicleId: map['vehicle_id'] as String,
      categoryId: map['category_id'] as String,
      eventDateTime: DateTime.parse(map['event_datetime'] as String),
      odometer: map['odometer'] as int?,
      amountMinor: map['amount_minor'] as int,
      merchant: map['merchant'] as String?,
      paymentMethod: map['payment_method'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
