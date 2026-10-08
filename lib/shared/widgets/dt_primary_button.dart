import 'package:flutter/material.dart';

import '../../app/theme/dt_tokens.dart';
import 'dt_motion.dart';

class DTPrimaryButton extends StatelessWidget {
  const DTPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final content = isLoading
        ? const SizedBox.square(
            key: ValueKey('loading'),
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          )
        : Text(
            label,
            key: ValueKey(label),
            overflow: TextOverflow.ellipsis,
          );
    final child = AnimatedSwitcher(
      duration: DTMotion.duration(context, DTDurations.fast),
      switchInCurve: DTMotion.standardCurve,
      switchOutCurve: Curves.easeInCubic,
      child: content,
    );

    if (icon == null || isLoading) {
      return DTPressable(
        enabled: onPressed != null && !isLoading,
        child: FilledButton(
          onPressed: isLoading ? null : onPressed,
          child: child,
        ),
      );
    }

    return DTPressable(
      enabled: onPressed != null,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: child,
      ),
    );
  }
}
