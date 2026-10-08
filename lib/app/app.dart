import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/database/app_database.dart';
import '../core/product_identity.dart';
import '../features/onboarding/presentation/welcome_screen.dart';
import '../shared/widgets/dt_empty_state.dart';
import '../shared/widgets/dt_motion.dart';
import 'app_controller.dart';
import 'drive_tracker_shell.dart';
import 'theme/dt_tokens.dart';
import 'theme/dt_theme.dart';

class DriveTrackerApp extends StatefulWidget {
  const DriveTrackerApp({required this.database, this.controller, super.key});

  final AppDatabase database;
  final DriveTrackerController? controller;

  @override
  State<DriveTrackerApp> createState() => _DriveTrackerAppState();
}

class _DriveTrackerAppState extends State<DriveTrackerApp> {
  late final DriveTrackerController _controller =
      widget.controller ?? DriveTrackerController(database: widget.database);

  @override
  void initState() {
    super.initState();
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _controller.dispose();
    unawaited(widget.database.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Consumer<DriveTrackerController>(
        builder: (context, controller, _) {
          return MaterialApp(
            title: ProductIdentity.name,
            debugShowCheckedModeBanner: false,
            theme: DTTheme.light(),
            darkTheme: DTTheme.dark(),
            themeMode: controller.themeMode,
            home: const _DriveTrackerBootstrap(),
          );
        },
      ),
    );
  }
}

class _DriveTrackerBootstrap extends StatelessWidget {
  const _DriveTrackerBootstrap();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    late final String screenKey;
    late final Widget screen;

    if (!controller.initialized) {
      screenKey = 'splash';
      screen = const _SplashScreen();
    } else if (controller.errorMessage != null && !controller.hasAnyVehicles) {
      screenKey = 'startup-error';
      screen = _StartupErrorScreen(message: controller.errorMessage!);
    } else if (!controller.hasAnyVehicles) {
      screenKey = 'welcome';
      screen = const WelcomeScreen();
    } else {
      screenKey = 'shell';
      screen = const DriveTrackerShell();
    }

    return AnimatedSwitcher(
      duration: DTMotion.duration(context, DTDurations.normal),
      switchInCurve: DTMotion.standardCurve,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        if (DTMotion.reduceMotion(context)) {
          return child;
        }
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey(screenKey), child: screen),
    );
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
