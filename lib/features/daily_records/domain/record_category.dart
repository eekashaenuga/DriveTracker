enum RecordCategoryType {
  expense('Expense', 'EXPENSE'),
  income('Income', 'INCOME'),
  maintenance('Maintenance', 'MAINTENANCE');

  const RecordCategoryType(this.label, this.storageValue);

  final String label;
  final String storageValue;

  static RecordCategoryType fromStorage(String value) {
    return RecordCategoryType.values.firstWhere(
      (type) => type.storageValue == value,
      orElse: () => RecordCategoryType.expense,
    );
  }
}

class RecordCategory {
  const RecordCategory({
    required this.id,
    required this.type,
    required this.name,
    required this.sortOrder,
    required this.systemCategory,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
    this.iconIdentifier,
  });

  final String id;
  final RecordCategoryType type;
  final String name;
  final int sortOrder;
  final bool systemCategory;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? iconIdentifier;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'type': type.storageValue,
      'name': name,
      'icon_identifier': iconIdentifier,
      'sort_order': sortOrder,
      'system_category': systemCategory ? 1 : 0,
      'is_archived': isArchived ? 1 : 0,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory RecordCategory.fromMap(Map<String, Object?> map) {
    return RecordCategory(
      id: map['id'] as String,
      type: RecordCategoryType.fromStorage(map['type'] as String),
      name: map['name'] as String,
      iconIdentifier: map['icon_identifier'] as String?,
      sortOrder: map['sort_order'] as int,
      systemCategory: map['system_category'] == 1,
      isArchived: map['is_archived'] == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
