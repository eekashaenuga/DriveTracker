import 'income_activity.dart';
import 'expense.dart';

class IncomeDraft {
  const IncomeDraft({
    required this.vehicleId,
    required this.categoryId,
    required this.eventDateTime,
    required this.amountMinor,
    this.activity = const IncomeActivity(),
    this.odometer,
    this.source,
    this.notes,
    this.linkedExpenseIds,
    this.newDirectExpenses = const [],
  });

  final String vehicleId;
  final String categoryId;
  final DateTime eventDateTime;
  final int amountMinor;
  final IncomeActivity activity;
  final int? odometer;
  final String? source;
  final String? notes;
  final List<String>? linkedExpenseIds;
  final List<ExpenseDraft> newDirectExpenses;
}

class Income {
  const Income({
    required this.id,
    required this.vehicleId,
    required this.categoryId,
    required this.eventDateTime,
    required this.amountMinor,
    required this.createdAt,
    required this.updatedAt,
    this.activity = const IncomeActivity(),
    this.odometer,
    this.source,
    this.notes,
  });

  final String id;
  final String vehicleId;
  final String categoryId;
  final DateTime eventDateTime;
  final IncomeActivity activity;
  final int? odometer;
  final int amountMinor;
  final String? source;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return {
      ...activity.toMap(),
      'id': id,
      'vehicle_id': vehicleId,
      'category_id': categoryId,
      'event_datetime': eventDateTime.toUtc().toIso8601String(),
      'odometer': odometer,
      'amount_minor': amountMinor,
      'source': source,
      'notes': notes,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory Income.fromMap(Map<String, Object?> map) {
    return Income(
      activity: IncomeActivity.fromMap(map),
      id: map['id'] as String,
      vehicleId: map['vehicle_id'] as String,
      categoryId: map['category_id'] as String,
      eventDateTime: DateTime.parse(map['event_datetime'] as String),
      odometer: map['odometer'] as int?,
      amountMinor: map['amount_minor'] as int,
      source: map['source'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
