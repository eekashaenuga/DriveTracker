import 'package:path/path.dart' as p;

enum AttachmentParentType {
  document('DOCUMENT', 'documents'),
  refuel('REFUEL', 'refuels'),
  service('SERVICE', 'services'),
  expense('EXPENSE', 'expenses'),
  income('INCOME', 'income'),
  vehicle('VEHICLE', 'vehicles');

  const AttachmentParentType(this.storageValue, this.storageSegment);

  final String storageValue;
  final String storageSegment;

  static AttachmentParentType fromStorage(String value) {
    for (final type in values) {
      if (type.storageValue == value) {
        return type;
      }
    }
    throw StateError('Unsupported attachment parent type $value.');
  }
}

class AttachmentSource {
  const AttachmentSource({
    required this.sourcePath,
    required this.fileName,
    this.mimeType,
    this.fileSize,
  });

  final String sourcePath;
  final String fileName;
  final String? mimeType;
  final int? fileSize;
}

class Attachment {
  const Attachment({
    required this.id,
    required this.parentType,
    required this.parentId,
    required this.fileName,
    required this.storedPath,
    required this.createdAt,
    required this.updatedAt,
    this.mimeType,
    this.fileSize,
  });

  final String id;
  final AttachmentParentType parentType;
  final String parentId;
  final String fileName;
  final String storedPath;
  final String? mimeType;
  final int? fileSize;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get extension {
    final extension = p.extension(fileName).replaceFirst('.', '').trim();
    if (extension.isNotEmpty) {
      return extension.toLowerCase();
    }
    return p.extension(storedPath).replaceFirst('.', '').toLowerCase();
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'parent_type': parentType.storageValue,
      'parent_id': parentId,
      'file_name': fileName,
      'stored_path': storedPath,
      'mime_type': mimeType,
      'file_size': fileSize,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory Attachment.fromMap(Map<String, Object?> map) {
    return Attachment(
      id: map['id'] as String,
      parentType: AttachmentParentType.fromStorage(
        map['parent_type'] as String,
      ),
      parentId: map['parent_id'] as String,
      fileName: map['file_name'] as String,
      storedPath: map['stored_path'] as String,
      mimeType: map['mime_type'] as String?,
      fileSize: map['file_size'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

enum AttachmentOpenStatus { opened, missing, failed, unavailable }

class AttachmentOpenResult {
  const AttachmentOpenResult(this.status, [this.message]);

  final AttachmentOpenStatus status;
  final String? message;

  bool get opened => status == AttachmentOpenStatus.opened;
}
