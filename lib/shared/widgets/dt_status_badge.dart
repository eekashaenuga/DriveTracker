import 'package:flutter/material.dart';

import '../../app/theme/dt_tokens.dart';

class DTStatusBadge extends StatelessWidget {
  const DTStatusBadge({
    required this.label,
    required this.color,
    this.icon,
    this.compact = false,
    super.key,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 168),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? DTSpacing.sm : DTSpacing.md,
            vertical: compact ? 3 : DTSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(DTRadii.card),
            border: Border.all(color: color.withValues(alpha: 0.34)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: DTIconSizes.sm, color: color),
                const SizedBox(width: DTSpacing.xs),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
