import 'dart:async';

import 'package:drivetracker/app/router/app_navigation.dart';
import 'package:drivetracker/app/theme/dt_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final data in [
    const MediaQueryData(),
    const MediaQueryData(disableAnimations: true),
    const MediaQueryData(accessibleNavigation: true),
  ]) {
    testWidgets('motion policy respects $data', (tester) async {
      late Duration duration;
      await tester.pumpWidget(
        MediaQuery(
          data: data,
          child: Builder(
            builder: (context) {
              duration = DTMotion.durationOf(
                context,
                const Duration(milliseconds: 200),
              );
              return const SizedBox();
            },
          ),
        ),
      );
      expect(
        duration,
        data.disableAnimations || data.accessibleNavigation
            ? Duration.zero
            : const Duration(milliseconds: 200),
      );
    });
  }
  for (final reduced in [false, true]) {
    testWidgets(
      'navigation uses Material transitions; reduced motion: $reduced',
      (tester) async {
        final observer = _RouteObserver();
        late BuildContext routeContext;
        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [observer],
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Builder(
                builder: (context) {
                  routeContext = context;
                  return TextButton(
                    onPressed: () {
                      unawaited(AppNavigation.openFuelCalculator(context));
                    },
                    child: const Text('Open'),
                  );
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        final route = observer.lastRoute!;
        expect(route, isA<MaterialPageRoute<void>>());
        const child = SizedBox(key: Key('transition-child'));
        final transition = (route as PageRoute<void>).buildTransitions(
          routeContext,
          const AlwaysStoppedAnimation(0.5),
          const AlwaysStoppedAnimation(0),
          child,
        );
        expect(identical(transition, child), reduced);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

class _RouteObserver extends NavigatorObserver {
  Route<dynamic>? lastRoute;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastRoute = route;
  }
}
