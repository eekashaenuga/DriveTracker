import 'date_reminder_schedule.dart';
import 'reminder_wording.dart';
import '../../../core/notifications/local_notification_service.dart';
import '../../documents/data/document_repository.dart';
import '../../documents/domain/vehicle_document.dart';
import '../../documents/domain/document_type.dart';
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

  final List<String> _buildFailures = [];

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
    final failures = <String>[];
    final cancelled = <int>{};
    final scheduled = <LocalNotificationRequest>[];
    Future<bool> cancel(int id) async {
      try {
        await _client.cancel(id);
        cancelled.add(id);
        return true;
      } catch (_) {
        failures.add('cancel:$id');
        return false;
      }
    }

    final permission = await _client.permissionStatus();
    if (!enabled || permission != LocalNotificationPermissionStatus.granted) {
      final ids = {...ownedPendingIds};
      if (_client is NotificationInteractionClient) {
        try {
          ids.addAll(
            (await (_client as NotificationInteractionClient)
                    .activeNotificationIds())
                .where(isDriveTrackerNotificationId),
          );
        } catch (_) {
          failures.add('active-notifications');
        }
      }
      for (final id in ids) {
        await cancel(id);
      }
      return ReminderNotificationReconciliation(
        scheduled: scheduled,
        cancelledIds: cancelled,
        failures: failures,
      );
    }
    final desired = await buildDateReminderRequests();
    failures.addAll(_buildFailures);
    final desiredIds = desired.map((r) => r.id).toSet();
    // If a source cannot be read, keep unknown old schedules until a successful
    // retry; still reconcile the other valid sources.
    if (_buildFailures.isEmpty) {
      for (final id in ownedPendingIds.difference(desiredIds)) {
        await cancel(id);
      }
    }
    for (final request in desired) {
      if (!await cancel(request.id)) continue;
      try {
        await _client.schedule(request);
        scheduled.add(request);
      } catch (_) {
        failures.add('schedule:${request.stableId}');
      }
    }
    return ReminderNotificationReconciliation(
      scheduled: scheduled,
      cancelledIds: cancelled,
      failures: failures,
    );
  }

  Future<List<LocalNotificationRequest>> buildDateReminderRequests() async {
    _buildFailures.clear();
    final now = _clock();
    final vehicles = await _vehicleRepository.listActive();
    final requests = <LocalNotificationRequest>[];

    for (final vehicle in vehicles) {
      List<MaintenanceReminder> maintenanceReminders = [];
      try {
        final currentOdometer = await _odometerRepository
            .currentOdometerForVehicle(vehicle.id);
        maintenanceReminders = await _maintenanceItemService
            .remindersForVehicle(
              vehicle.id,
              currentOdometer: currentOdometer,
              asOf: now,
            );
      } catch (_) {
        _buildFailures.add('maintenance:${vehicle.id}');
      }
      for (final reminder in maintenanceReminders) {
        if (!reminder.shouldShowAsReminder || reminder.nextDateDue == null) {
          continue;
        }
        try {
          final schedule = reminder.item.reminderSchedule;
          if (schedule == null && !reminder.item.isExpiry) {
            requests.add(_maintenanceRequest(vehicle, reminder, now));
          } else {
            requests.addAll(
              _multipleRequests(
                namespace: 'maintenance_date',
                recordId: reminder.item.id,
                vehicle: vehicle,
                name: reminder.item.name,
                due: reminder.nextDateDue!,
                schedule: schedule ?? DateReminderSchedule.standard,
                now: now,
                expiry: reminder.item.isExpiry,
                mot: reminder.item.isMot,
              ),
            );
          }
        } catch (_) {
          _buildFailures.add('maintenance:${reminder.item.id}');
        }
      }

      List<VehicleDocument> documents = [];
      try {
        documents = await _documentRepository.activeExpiringForVehicle(
          vehicle.id,
        );
      } catch (_) {
        _buildFailures.add('documents:${vehicle.id}');
      }
      for (final document in documents) {
        final expiry = document.expiryDate;
        if (expiry == null) {
          continue;
        }
        try {
          final schedule = document.reminderSchedule;
          if (schedule == null) {
            requests.add(_documentRequest(vehicle, document, expiry, now));
          } else {
            requests.addAll(
              _multipleRequests(
                namespace: 'document_date',
                recordId: document.id,
                vehicle: vehicle,
                name: document.category,
                due: expiry,
                schedule: schedule,
                now: now,
                expiry: document.type != DocumentType.tax,
                mot: document.type == DocumentType.mot,
              ),
            );
          }
        } catch (_) {
          _buildFailures.add('document:${document.id}');
        }
      }
    }

    requests.sort((a, b) {
      final scheduleCompare = a.scheduledAt.compareTo(b.scheduledAt);
      if (scheduleCompare != 0) {
        return scheduleCompare;
      }
      return a.stableId.compareTo(b.stableId);
    });
    final used = <int>{};
    final allocated = <String, int>{};
    final stableOrder = [...requests]
      ..sort((a, b) => a.stableId.compareTo(b.stableId));
    for (final request in stableOrder) {
      var id = request.id;
      while (!used.add(id)) {
        id =
            _notificationIdBase +
            ((id - _notificationIdBase + 1) % _notificationIdSpan);
      }
      allocated[request.stableId] = id;
    }
    return [
      for (final r in requests)
        LocalNotificationRequest(
          id: allocated[r.stableId]!,
          stableId: r.stableId,
          title: r.title,
          body: r.body,
          scheduledAt: r.scheduledAt,
          payload: r.payload,
        ),
    ];
  }

  List<LocalNotificationRequest> _multipleRequests({
    required String namespace,
    required String recordId,
    required Vehicle vehicle,
    required String name,
    required DateTime due,
    required DateReminderSchedule schedule,
    required DateTime now,
    required bool expiry,
    required bool mot,
  }) {
    return [
      for (final at in schedule.notificationTimes(due, now))
        _datedRequest(namespace, recordId, vehicle, name, due, at, expiry, mot),
    ];
  }

  LocalNotificationRequest _datedRequest(
    String namespace,
    String recordId,
    Vehicle vehicle,
    String name,
    DateTime due,
    DateTime at,
    bool expiry,
    bool mot,
  ) {
    final key = '${namespace}_${recordId}_${at.year}-${at.month}-${at.day}';
    final wording = ReminderWording.message(
      vehicle: vehicle.name,
      name: name,
      due: due,
      asOf: at,
      expiry: expiry,
      mot: mot,
    );
    return LocalNotificationRequest(
      id: notificationIdForStableId(key),
      stableId: key,
      title: wording.title,
      body: wording.body,
      scheduledAt: at,
      payload: '${namespace}_$recordId',
    );
  }

  LocalNotificationRequest _maintenanceRequest(
    Vehicle vehicle,
    MaintenanceReminder reminder,
    DateTime now,
  ) {
    final dueDate = _dateOnly(reminder.nextDateDue!);
    final stableId = 'maintenance_date_${reminder.item.id}';
    final scheduledAt = _scheduledReminderTime(
      dueDate: dueDate,
      warningDays: reminder.item.dateWarningDays,
      now: now,
    );
    final wording = ReminderWording.message(
      vehicle: vehicle.name,
      name: reminder.item.name,
      due: dueDate,
      asOf: scheduledAt,
      expiry: false,
    );
    return LocalNotificationRequest(
      id: notificationIdForStableId(stableId),
      stableId: stableId,
      title: wording.title,
      body: wording.body,
      scheduledAt: scheduledAt,
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
    final scheduledAt = _scheduledReminderTime(
      dueDate: dueDate,
      warningDays: DocumentExpiryReminder.expiringSoonDays,
      now: now,
    );
    final wording = ReminderWording.message(
      vehicle: vehicle.name,
      name: document.category,
      due: dueDate,
      asOf: scheduledAt,
      expiry: document.type != DocumentType.tax,
      mot: document.type == DocumentType.mot,
    );
    return LocalNotificationRequest(
      id: notificationIdForStableId(stableId),
      stableId: stableId,
      title: wording.title,
      body: wording.body,
      scheduledAt: scheduledAt,
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
    final warningDate = DateTime(
      localDueDate.year,
      localDueDate.month,
      localDueDate.day - (warningDays < 0 ? 0 : warningDays),
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
}

class ReminderNotificationReconciliation {
  const ReminderNotificationReconciliation({
    required this.scheduled,
    required this.cancelledIds,
    this.failures = const [],
  });

  final List<LocalNotificationRequest> scheduled;
  final Set<int> cancelledIds;
  final List<String> failures;
  bool get isPartial => failures.isNotEmpty;
}
