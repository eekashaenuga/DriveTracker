import 'package:flutter/material.dart';

import '../../app/theme/dt_tokens.dart';

class DTMotion {
  const DTMotion._();

  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve emphasizedCurve = Curves.easeOutQuart;

  static bool reduceMotion(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    return media?.disableAnimations == true ||
        media?.accessibleNavigation == true;
  }

  static Duration duration(BuildContext context, Duration duration) {
    return reduceMotion(context) ? Duration.zero : duration;
  }
}

class DTPressable extends StatefulWidget {
  const DTPressable({
    required this.child,
    this.enabled = true,
    this.hoverScale = 1.01,
    this.pressedScale = 0.985,
    this.pressedOpacity = 0.96,
    super.key,
  });

  final Widget child;
  final bool enabled;
  final double hoverScale;
  final double pressedScale;
  final double pressedOpacity;

  @override
  State<DTPressable> createState() => _DTPressableState();
}

class _DTPressableState extends State<DTPressable> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = DTMotion.reduceMotion(context);
    final canAnimate = widget.enabled && !reduceMotion;
    final scale = !canAnimate
        ? 1.0
        : _pressed
        ? widget.pressedScale
        : _hovered
        ? widget.hoverScale
        : 1.0;
    final opacity = canAnimate && _pressed ? widget.pressedOpacity : 1.0;
    final duration = DTMotion.duration(context, DTDurations.fast);

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) {
        _setHovered(false);
        _setPressed(false);
      },
      child: Listener(
        onPointerDown: widget.enabled ? (_) => _setPressed(true) : null,
        onPointerUp: widget.enabled ? (_) => _setPressed(false) : null,
        onPointerCancel: widget.enabled ? (_) => _setPressed(false) : null,
        child: AnimatedScale(
          scale: scale,
          duration: duration,
          curve: DTMotion.standardCurve,
          child: AnimatedOpacity(
            opacity: opacity,
            duration: duration,
            curve: DTMotion.standardCurve,
            child: widget.child,
          ),
        ),
      ),
    );
  }

  void _setHovered(bool hovered) {
    if (_hovered == hovered || !mounted) {
      return;
    }
    setState(() => _hovered = hovered);
  }

  void _setPressed(bool pressed) {
    if (_pressed == pressed || !mounted) {
      return;
    }
    setState(() => _pressed = pressed);
  }
}

class DTAnimatedEntrance extends StatelessWidget {
  const DTAnimatedEntrance({
    required this.child,
    this.order = 0,
    this.offset = const Offset(0, 12),
    super.key,
  });

  final Widget child;
  final int order;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    if (DTMotion.reduceMotion(context)) {
      return child;
    }

    final delayFraction = (order * 0.07).clamp(0.0, 0.42);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: DTDurations.slow,
      curve: Curves.linear,
      builder: (context, value, child) {
        final rawProgress = value <= delayFraction
            ? 0.0
            : ((value - delayFraction) / (1 - delayFraction)).clamp(0.0, 1.0);
        final progress = DTMotion.emphasizedCurve.transform(rawProgress);
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: offset * (1 - progress),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
