class BackupManifest {
  const BackupManifest({
    required this.backupFormatVersion,
    required this.schemaVersion,
    required this.createdAtUtc,
    required this.databasePath,
    required this.databaseBytes,
    required this.tableCounts,
    required this.attachments,
  });

  final int backupFormatVersion;
  final int schemaVersion;
  final DateTime createdAtUtc;
  final String databasePath;
  final int databaseBytes;
  final Map<String, int> tableCounts;
  final List<BackupAttachmentEntry> attachments;

  int get attachmentCount => attachments.length;

  Map<String, Object?> toJson() {
    return {
      'app': 'DriveTracker',
      'backupFormatVersion': backupFormatVersion,
      'schemaVersion': schemaVersion,
      'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
      'database': {'path': databasePath, 'bytes': databaseBytes},
      'tableCounts': tableCounts,
      'attachments': [
        for (final attachment in attachments) attachment.toJson(),
      ],
    };
  }

  factory BackupManifest.fromJson(Map<String, Object?> json) {
    final database = _asMap(json['database'], 'database');
    final counts = _asMap(json['tableCounts'], 'tableCounts');
    final attachments = _asList(json['attachments'], 'attachments');
    return BackupManifest(
      backupFormatVersion: _asInt(
        json['backupFormatVersion'],
        'backupFormatVersion',
      ),
      schemaVersion: _asInt(json['schemaVersion'], 'schemaVersion'),
      createdAtUtc: DateTime.parse(
        _asString(json['createdAtUtc'], 'createdAtUtc'),
      ),
      databasePath: _asString(database['path'], 'database.path'),
      databaseBytes: _asInt(database['bytes'], 'database.bytes'),
      tableCounts: {
        for (final entry in counts.entries)
          entry.key: _asInt(entry.value, 'tableCounts.${entry.key}'),
      },
      attachments: [
        for (var index = 0; index < attachments.length; index += 1)
          BackupAttachmentEntry.fromJson(
            _asMap(attachments[index], 'attachments[$index]'),
          ),
      ],
    );
  }
}

class BackupAttachmentEntry {
  const BackupAttachmentEntry({
    required this.id,
    required this.storedPath,
    required this.archivePath,
    required this.fileName,
    required this.fileSize,
    required this.parentType,
    required this.parentId,
    this.mimeType,
  });

  final String id;
  final String storedPath;
  final String archivePath;
  final String fileName;
  final int fileSize;
  final String parentType;
  final String parentId;
  final String? mimeType;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'storedPath': storedPath,
      'archivePath': archivePath,
      'fileName': fileName,
      'fileSize': fileSize,
      'parentType': parentType,
      'parentId': parentId,
      'mimeType': mimeType,
    };
  }

  factory BackupAttachmentEntry.fromJson(Map<String, Object?> json) {
    return BackupAttachmentEntry(
      id: _asString(json['id'], 'attachment.id'),
      storedPath: _asString(json['storedPath'], 'attachment.storedPath'),
      archivePath: _asString(json['archivePath'], 'attachment.archivePath'),
      fileName: _asString(json['fileName'], 'attachment.fileName'),
      fileSize: _asInt(json['fileSize'], 'attachment.fileSize'),
      parentType: _asString(json['parentType'], 'attachment.parentType'),
      parentId: _asString(json['parentId'], 'attachment.parentId'),
      mimeType: json['mimeType'] == null
          ? null
          : _asString(json['mimeType'], 'attachment.mimeType'),
    );
  }
}

Map<String, Object?> _asMap(Object? value, String field) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): entry.value as Object?,
    };
  }
  throw FormatException('Backup manifest field "$field" is invalid.');
}

List<Object?> _asList(Object? value, String field) {
  if (value is List) {
    return value.cast<Object?>();
  }
  throw FormatException('Backup manifest field "$field" is invalid.');
}

String _asString(Object? value, String field) {
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('Backup manifest field "$field" is invalid.');
}

int _asInt(Object? value, String field) {
  if (value is int) {
    return value;
  }
  throw FormatException('Backup manifest field "$field" is invalid.');
}
