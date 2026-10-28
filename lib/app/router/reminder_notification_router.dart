import 'dart:collection';

import '../../core/notifications/notification_target.dart';
import '../app_controller.dart';
import '../../features/documents/domain/document_type.dart';

class ReminderNotificationDestination {
  const ReminderNotificationDestination({
    this.vehicleId,
    this.target,
    this.review = false,
    this.message,
  });
  final String? vehicleId, message;
  final NotificationTarget? target;
  final bool review;
}

/// In-memory only. No notification history, persistence or change to scheduling IDs.
class ReminderNotificationRouter {
  ReminderNotificationRouter({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  final Queue<NotificationTarget> _queue = Queue();
  String? _lastKey;
  DateTime? _lastTap;
  bool _opening = false;
  int get pendingCount => _queue.length;
  void enqueue(NotificationTarget target) {
    final now = _clock();
    if (_lastKey == target.key &&
        _lastTap != null &&
        now.difference(_lastTap!).inMilliseconds.abs() < 2000) {
      return;
    }
    _lastKey = target.key;
    _lastTap = now;
    _queue.add(target);
  }

  Future<void> drain({
    required bool ready,
    required Future<void> Function(NotificationTarget) open,
  }) async {
    if (!ready || _opening) return;
    _opening = true;
    try {
      while (_queue.isNotEmpty) {
        await open(_queue.removeFirst());
      }
    } finally {
      _opening = false;
    }
  }
}

Future<ReminderNotificationDestination> resolveReminderNotification(
  DriveTrackerController c,
  NotificationTarget target,
) async {
  if (target.source == NotificationSource.reminders) {
    return const ReminderNotificationDestination();
  }
  String? vehicleId;
  bool archived = true;
  bool mot = false;
  if (target.source == NotificationSource.document) {
    final record = await c.documentById(target.recordId);
    vehicleId = record?.vehicleId;
    archived = record?.isArchived ?? true;
    mot = record?.type == DocumentType.mot;
  } else {
    final record = await c.maintenanceItemById(target.recordId);
    vehicleId = record?.vehicleId;
    archived = record?.isArchived ?? true;
    mot =
        record != null &&
        DocumentType.classify(record.category ?? record.name) ==
            DocumentType.mot;
  }
  if (archived || !c.activeVehicles.any((v) => v.id == vehicleId)) {
    return const ReminderNotificationDestination(
      message: 'This reminder record is archived or no longer available.',
    );
  }
  final conflict = mot && await c.hasMotConflict(vehicleId!);
  return ReminderNotificationDestination(
    vehicleId: vehicleId,
    target: target,
    review: conflict,
  );
}
