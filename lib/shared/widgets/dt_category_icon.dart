import 'package:flutter/material.dart';

import '../../app/theme/dt_tokens.dart';

class DTCategoryIcon extends StatelessWidget {
  const DTCategoryIcon({
    required this.icon,
    required this.color,
    this.size = 42,
    this.iconSize = DTIconSizes.md,
    this.tooltip,
    super.key,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final icon = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(DTRadii.card),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Icon(this.icon, color: color, size: iconSize),
    );
    final tooltip = this.tooltip;
    if (tooltip == null) {
      return icon;
    }
    return Tooltip(message: tooltip, child: icon);
  }
}
