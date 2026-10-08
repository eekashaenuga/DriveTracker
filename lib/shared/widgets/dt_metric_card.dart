import 'package:flutter/material.dart';

import '../../app/theme/dt_tokens.dart';

class DTMetricCard extends StatelessWidget {
  const DTMetricCard({
    required this.label,
    required this.value,
    this.icon,
    this.accentColor,
    this.supportingText,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? accentColor;
  final String? supportingText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = accentColor ?? colors.primary;

    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.44),
      borderRadius: DTRadii.cardRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: DTRadii.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(DTSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: DTIconSizes.sm, color: accent),
                    const SizedBox(width: DTSpacing.sm),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colors.onSurfaceVariant,
                      size: DTIconSizes.sm,
                    ),
                ],
              ),
              const SizedBox(height: DTSpacing.md),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (supportingText != null) ...[
                const SizedBox(height: DTSpacing.xs),
                Text(
                  supportingText!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
