import 'dart:convert';

enum NotificationSource { maintenance, document, reminders }

/// Routing data only. Scheduling IDs and existing payloads remain compatible.
class NotificationTarget {
  const NotificationTarget(this.source, this.recordId);
  const NotificationTarget.overview()
    : source = NotificationSource.reminders,
      recordId = '';
  final NotificationSource source;
  final String recordId;
  String get key => '${source.name}:$recordId';
  static NotificationTarget? parse(String? payload) {
    if (payload == null || payload.length > 1024) return null;
    NotificationSource? source;
    String? id;
    if (payload.startsWith('maintenance_date_')) {
      source = NotificationSource.maintenance;
      id = payload.substring(17);
    } else if (payload.startsWith('document_date_')) {
      source = NotificationSource.document;
      id = payload.substring(14);
    } else {
      try {
        final map = jsonDecode(payload);
        if (map is! Map || map['v'] != 1) return null;
        source = switch (map['source']) {
          'maintenance' => NotificationSource.maintenance,
          'document' => NotificationSource.document,
          _ => null,
        };
        id = map['id'] is String ? map['id'] as String : null;
      } catch (_) {
        return null;
      }
    }
    if (source == null ||
        id == null ||
        !RegExp(r'^[A-Za-z0-9_-]{1,200}$').hasMatch(id)) {
      return null;
    }
    return NotificationTarget(source, id);
  }
}
