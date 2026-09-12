import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

enum LocalNotificationPermissionStatus { unsupported, denied, granted }

class LocalNotificationRequest {
  const LocalNotificationRequest({
    required this.id,
    required this.stableId,
    required this.title,
    required this.body,
    required this.scheduledAt,
    required this.payload,
  });

  final int id;
  final String stableId;
  final String title;
  final String body;
  final DateTime scheduledAt;
  final String payload;
}

abstract class LocalNotificationClient {
  bool get isSupported;

  Future<void> initialize();

  Future<LocalNotificationPermissionStatus> permissionStatus();

  Future<LocalNotificationPermissionStatus> requestPermission();

  Future<List<int>> pendingNotificationIds();

  Future<void> schedule(LocalNotificationRequest request);

  Future<void> cancel(int id);
}

LocalNotificationClient defaultLocalNotificationClient() {
  if (!kIsWeb && Platform.isAndroid) {
    return FlutterLocalNotificationClient();
  }
  return const NoopLocalNotificationClient();
}

class NoopLocalNotificationClient implements LocalNotificationClient {
  const NoopLocalNotificationClient();

  @override
  bool get isSupported => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<LocalNotificationPermissionStatus> permissionStatus() async {
    return LocalNotificationPermissionStatus.unsupported;
  }

  @override
  Future<LocalNotificationPermissionStatus> requestPermission() async {
    return LocalNotificationPermissionStatus.unsupported;
  }

  @override
  Future<List<int>> pendingNotificationIds() async => const [];

  @override
  Future<void> schedule(LocalNotificationRequest request) async {}

  @override
  Future<void> cancel(int id) async {}
}

class FlutterLocalNotificationClient implements LocalNotificationClient {
  FlutterLocalNotificationClient({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _androidSettings = AndroidInitializationSettings(
    '@mipmap/ic_launcher',
  );
  static const _initializationSettings = InitializationSettings(
    android: _androidSettings,
  );
  static const _androidDetails = AndroidNotificationDetails(
    'drive_tracker_reminders',
    'DriveTracker reminders',
    channelDescription:
        'Local reminders for vehicle documents and scheduled maintenance.',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    category: AndroidNotificationCategory.reminder,
    visibility: NotificationVisibility.private,
  );
  static const _notificationDetails = NotificationDetails(
    android: _androidDetails,
  );

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  @override
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  @override
  Future<void> initialize() async {
    if (_initialized || !isSupported) {
      return;
    }

    tz_data.initializeTimeZones();
    try {
      final timeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZone.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    await _plugin.initialize(settings: _initializationSettings);
    _initialized = true;
  }

  @override
  Future<LocalNotificationPermissionStatus> permissionStatus() async {
    if (!isSupported) {
      return LocalNotificationPermissionStatus.unsupported;
    }
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final enabled = await android?.areNotificationsEnabled() ?? false;
    return enabled
        ? LocalNotificationPermissionStatus.granted
        : LocalNotificationPermissionStatus.denied;
  }

  @override
  Future<LocalNotificationPermissionStatus> requestPermission() async {
    if (!isSupported) {
      return LocalNotificationPermissionStatus.unsupported;
    }
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final granted = await android?.requestNotificationsPermission() ?? false;
    return granted
        ? LocalNotificationPermissionStatus.granted
        : LocalNotificationPermissionStatus.denied;
  }

  @override
  Future<List<int>> pendingNotificationIds() async {
    if (!isSupported) {
      return const [];
    }
    await initialize();
    final pending = await _plugin.pendingNotificationRequests();
    return [for (final request in pending) request.id];
  }

  @override
  Future<void> schedule(LocalNotificationRequest request) async {
    if (!isSupported) {
      return;
    }
    await initialize();
    await _plugin.zonedSchedule(
      id: request.id,
      title: request.title,
      body: request.body,
      scheduledDate: tz.TZDateTime.from(request.scheduledAt, tz.local),
      notificationDetails: _notificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: request.payload,
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (!isSupported) {
      return;
    }
    await initialize();
    await _plugin.cancel(id: id);
  }
}
