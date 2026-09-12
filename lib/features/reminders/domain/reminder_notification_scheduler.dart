import '../../../core/notifications/local_notification_service.dart';
import '../../documents/data/document_repository.dart';
import '../../documents/domain/vehicle_document.dart';
import '../../maintenance/domain/maintenance_item_service.dart';
import '../../maintenance/domain/maintenance_reminder.dart';
import '../../odometer/data/odometer_repository.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../../vehicles/domain/vehicle.dart';

class ReminderNotificationScheduler {
  factory ReminderNotificationScheduler({
    required LocalNotificationClient client,
    required VehicleRepository vehicleRepository,
    required OdometerRepository odometerRepository,
    required MaintenanceItemService maintenanceItemService,
    required DocumentRepository documentRepository,
    required DateTime Function() clock,
  }) {
    return ReminderNotificationScheduler._(
      client,
      vehicleRepository,
      odometerRepository,
      maintenanceItemService,
      documentRepository,
      clock,
    );
  }

  ReminderNotificationScheduler._(
    this._client,
    this._vehicleRepository,
    this._odometerRepository,
    this._maintenanceItemService,
    this._documentRepository,
    this._clock,
  );

  static const notificationHour = 9;
  static const _notificationIdBase = 100000000;
  static const _notificationIdSpan = 900000000;

  final LocalNotificationClient _client;
  final VehicleRepository _vehicleRepository;
  final OdometerRepository _odometerRepository;
  final MaintenanceItemService _maintenanceItemService;
  final DocumentRepository _documentRepository;
  final DateTime Function() _clock;

  bool get isSupported => _client.isSupported;

  Future<LocalNotificationPermissionStatus> permissionStatus() {
    return _client.permissionStatus();
  }

  Future<LocalNotificationPermissionStatus> requestPermission() {
    return _client.requestPermission();
  }

  Future<ReminderNotificationReconciliation> reconcile({
    required bool enabled,
  }) async {
    await _client.initialize();

    final pendingIds = await _client.pendingNotificationIds();
    final ownedPendingIds = pendingIds
        .where(isDriveTrackerNotificationId)
        .toSet();

    final permission = await _client.permissionStatus();
    if (!enabled || permission != LocalNotificationPermissionStatus.granted) {
      for (final id in ownedPendingIds) {
        await _client.cancel(id);
      }
      return ReminderNotificationReconciliation(
        scheduled: const [],
        cancelledIds: ownedPendingIds,
      );
    }

    final desired = await buildDateReminderRequests();
    final desiredIds = {for (final request in desired) request.id};
    final staleIds = ownedPendingIds.difference(desiredIds);

    for (final id in staleIds) {
      await _client.cancel(id);
    }
    for (final request in desired) {
      await _client.cancel(request.id);
      await _client.schedule(request);
    }

    return ReminderNotificationReconciliation(
      scheduled: desired,
      cancelledIds: {...staleIds, ...desiredIds.intersection(ownedPendingIds)},
    );
  }

  Future<List<LocalNotificationRequest>> buildDateReminderRequests() async {
    final now = _clock();
    final vehicles = await _vehicleRepository.listActive();
    final requests = <LocalNotificationRequest>[];

    for (final vehicle in vehicles) {
      final currentOdometer = await _odometerRepository
          .currentOdometerForVehicle(vehicle.id);
      final maintenanceReminders = await _maintenanceItemService
          .remindersForVehicle(
            vehicle.id,
            currentOdometer: currentOdometer,
            asOf: now,
          );
      for (final reminder in maintenanceReminders) {
        if (!reminder.shouldShowAsReminder || reminder.nextDateDue == null) {
          continue;
        }
        requests.add(_maintenanceRequest(vehicle, reminder, now));
      }

      final documents = await _documentRepository.activeExpiringForVehicle(
        vehicle.id,
      );
      for (final document in documents) {
        final expiry = document.expiryDate;
        if (expiry == null) {
          continue;
        }
        requests.add(_documentRequest(vehicle, document, expiry, now));
      }
    }

    requests.sort((a, b) {
      final scheduleCompare = a.scheduledAt.compareTo(b.scheduledAt);
      if (scheduleCompare != 0) {
        return scheduleCompare;
      }
      return a.stableId.compareTo(b.stableId);
    });
    return requests;
  }

  LocalNotificationRequest _maintenanceRequest(
    Vehicle vehicle,
    MaintenanceReminder reminder,
    DateTime now,
  ) {
    final dueDate = _dateOnly(reminder.nextDateDue!);
    final stableId = 'maintenance_date_${reminder.item.id}';
    return LocalNotificationRequest(
      id: notificationIdForStableId(stableId),
      stableId: stableId,
      title: 'DriveTracker',
      body:
          '${vehicle.name} - ${reminder.item.name} '
          '${_duePhrase(dueDate, now)}',
      scheduledAt: _scheduledReminderTime(
        dueDate: dueDate,
        warningDays: reminder.item.dateWarningDays,
        now: now,
      ),
      payload: stableId,
    );
  }

  LocalNotificationRequest _documentRequest(
    Vehicle vehicle,
    VehicleDocument document,
    DateTime expiryDate,
    DateTime now,
  ) {
    final dueDate = _dateOnly(expiryDate);
    final stableId = 'document_date_${document.id}';
    return LocalNotificationRequest(
      id: notificationIdForStableId(stableId),
      stableId: stableId,
      title: 'DriveTracker',
      body:
          '${vehicle.name} - ${document.category} '
          '${_expiryPhrase(dueDate, now)}',
      scheduledAt: _scheduledReminderTime(
        dueDate: dueDate,
        warningDays: DocumentExpiryReminder.expiringSoonDays,
        now: now,
      ),
      payload: stableId,
    );
  }

  static bool isDriveTrackerNotificationId(int id) {
    return id >= _notificationIdBase &&
        id < _notificationIdBase + _notificationIdSpan;
  }

  static int notificationIdForStableId(String stableId) {
    const fnvOffset = 0x811c9dc5;
    const fnvPrime = 0x01000193;
    var hash = fnvOffset;
    for (final codeUnit in stableId.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * fnvPrime) & 0xffffffff;
    }
    return _notificationIdBase + (hash % _notificationIdSpan);
  }

  static DateTime _scheduledReminderTime({
    required DateTime dueDate,
    required int warningDays,
    required DateTime now,
  }) {
    final localNow = now.toLocal();
    final localDueDate = _dateOnly(dueDate);
    final warningDate = localDueDate.subtract(
      Duration(days: warningDays < 0 ? 0 : warningDays),
    );
    final preferred = _atNotificationTime(warningDate);
    if (preferred.isAfter(localNow)) {
      return preferred;
    }

    final nextDaytime = _nextNotificationTime(localNow);
    final dueDaytime = _atNotificationTime(localDueDate);
    if (dueDaytime.isAfter(localNow) && dueDaytime.isBefore(nextDaytime)) {
      return dueDaytime;
    }
    return nextDaytime;
  }

  static DateTime _nextNotificationTime(DateTime now) {
    final today = _atNotificationTime(now);
    if (today.isAfter(now)) {
      return today;
    }
    return _atNotificationTime(now.add(const Duration(days: 1)));
  }

  static DateTime _atNotificationTime(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day, notificationHour);
  }

  static DateTime _dateOnly(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static String _duePhrase(DateTime dueDate, DateTime now) {
    final dayDifference = dueDate.difference(_dateOnly(now)).inDays;
    if (dayDifference < 0) {
      return 'overdue since ${_formatDay(dueDate)}';
    }
    if (dayDifference == 0) {
      return 'due today';
    }
    return 'due on ${_formatDay(dueDate)}';
  }

  static String _expiryPhrase(DateTime dueDate, DateTime now) {
    final dayDifference = dueDate.difference(_dateOnly(now)).inDays;
    if (dayDifference < 0) {
      return 'expired on ${_formatDay(dueDate)}';
    }
    if (dayDifference == 0) {
      return 'expires today';
    }
    return 'expires on ${_formatDay(dueDate)}';
  }

  static String _formatDay(DateTime value) {
    final local = value.toLocal();
    return '${local.day} ${_monthShort(local.month)} ${local.year}';
  }

  static String _monthShort(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}

class ReminderNotificationReconciliation {
  const ReminderNotificationReconciliation({
    required this.scheduled,
    required this.cancelledIds,
  });

  final List<LocalNotificationRequest> scheduled;
  final Set<int> cancelledIds;
}
