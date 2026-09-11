import 'package:flutter/material.dart';

import '../../app/theme/dt_tokens.dart';
import 'dt_category_icon.dart';

class DTListCard extends StatelessWidget {
  const DTListCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.enabled = true,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final bool enabled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final effectiveOnTap = enabled ? onTap : null;
    return Semantics(
      button: effectiveOnTap != null,
      selected: selected,
      label: semanticLabel ?? title,
      child: Material(
        color: selected
            ? accentColor.withValues(alpha: 0.16)
            : colors.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: DTRadii.cardRadius,
        child: InkWell(
          borderRadius: DTRadii.cardRadius,
          onTap: effectiveOnTap,
          child: Padding(
            padding: const EdgeInsets.all(DTSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DTCategoryIcon(icon: icon, color: accentColor),
                const SizedBox(width: DTSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: enabled
                              ? colors.onSurface
                              : colors.onSurface.withValues(alpha: 0.55),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: DTSpacing.xs),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: DTSpacing.md),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      maxWidth: 96,
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: trailing!,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
