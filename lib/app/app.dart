import '../features/reports/domain/report_service.dart';
import '../features/reports/data/report_repository.dart';
import 'router/reminder_notification_router.dart';
import 'router/app_navigation.dart';
import '../core/notifications/notification_target.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/database/app_database.dart';
import '../core/product_identity.dart';
import '../features/onboarding/presentation/welcome_screen.dart';
import '../shared/widgets/dt_empty_state.dart';
import 'app_controller.dart';
import 'drive_tracker_shell.dart';
import 'theme/dt_theme.dart';

class DriveTrackerApp extends StatefulWidget {
  const DriveTrackerApp({required this.database, this.controller, super.key});

  final AppDatabase database;
  final DriveTrackerController? controller;

  @override
  State<DriveTrackerApp> createState() => _DriveTrackerAppState();
}

class _DriveTrackerAppState extends State<DriveTrackerApp>
    with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _notificationRouter = ReminderNotificationRouter();
  bool _navigationScheduled = false, _backgrounded = false;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgrounded = true;
    }
    if (state == AppLifecycleState.resumed) {
      if (_backgrounded) {
        _backgrounded = false;
        unawaited(_controller.refreshReminderEnvironment(force: true));
      }
      _handleController();
    }
  }

  void _showScopedReminders(ReminderNotificationDestination destination) {
    final navigator = _navigatorKey.currentState;
    if (!mounted || navigator == null) return;
    unawaited(
      AppNavigation.openReminders(
        navigator.overlay!.context,
        vehicleId: destination.vehicleId,
      ),
    );
  }

  void _showNotificationDestination(
    ReminderNotificationDestination destination,
  ) {
    final navigator = _navigatorKey.currentState;
    if (!mounted || navigator == null) return;
    final routeContext = navigator.overlay!.context;
    if (destination.message != null) {
      ScaffoldMessenger.of(routeContext)
          .showSnackBar(SnackBar(content: Text(destination.message!)));
      return;
    }
    if (destination.review) {
      unawaited(
        AppNavigation.openDocuments(
          routeContext,
          vehicleId: destination.vehicleId,
        ),
      );
    } else if (destination.target?.source == NotificationSource.document) {
      unawaited(
        AppNavigation.openDocumentDetails(
          routeContext,
          destination.target!.recordId,
        ),
      );
    } else if (destination.target?.source == NotificationSource.maintenance) {
      unawaited(
        AppNavigation.openMaintenanceItemDetails(
          routeContext,
          destination.target!.recordId,
        ),
      );
    }
  }

  void _handleController() {
    for (final target in _controller.takeNotificationTargets()) {
      _notificationRouter.enqueue(target);
    }
    if (!mounted ||
        _navigationScheduled ||
        !_controller.initialized ||
        _notificationRouter.pendingCount == 0) {
      return;
    }
    _navigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _navigationScheduled = false;
      if (!mounted) return;
      await _notificationRouter.drain(
        ready: _navigatorKey.currentState != null,
        open: (target) async {
          try {
            final destination = await resolveReminderNotification(
              _controller,
              target,
            );
            if (!mounted) return;
            _showScopedReminders(destination);
            await WidgetsBinding.instance.endOfFrame;
            if (mounted) _showNotificationDestination(destination);
          } catch (_) {
            if (mounted) {
              _showScopedReminders(
                const ReminderNotificationDestination(
                  message: 'Could not open this notification record.',
                ),
              );
            }
          }
        },
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  late final DriveTrackerController _controller =
      widget.controller ?? DriveTrackerController(database: widget.database);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_handleController);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleController();
    });
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_handleController);
    _controller.dispose();
    unawaited(widget.database.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Provider<ReportService>(
      create: (_) => ReportService(ReportRepository(widget.database)),
      child: ChangeNotifierProvider.value(
        value: _controller,
        child: Consumer<DriveTrackerController>(
          builder: (context, controller, _) {
            return MaterialApp(
              navigatorKey: _navigatorKey,
              title: ProductIdentity.name,
              debugShowCheckedModeBanner: false,
              theme: DTTheme.light(),
              darkTheme: DTTheme.dark(),
              themeMode: controller.themeMode,
              home: const _DriveTrackerBootstrap(),
            );
          },
        ),
      ),
    );
  }
}

class _DriveTrackerBootstrap extends StatelessWidget {
  const _DriveTrackerBootstrap();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    if (!controller.initialized) {
      return const _SplashScreen();
    }
    if (controller.errorMessage != null && !controller.hasAnyVehicles) {
      return _StartupErrorScreen(message: controller.errorMessage!);
    }
    if (!controller.hasAnyVehicles) {
      return const WelcomeScreen();
    }
    return const DriveTrackerShell();
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DTEmptyState(
        icon: Icons.storage_rounded,
        title: 'Local data unavailable',
        body: message,
      ),
    );
  }
}
