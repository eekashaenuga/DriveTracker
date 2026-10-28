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
    this.subtitleMaxLines = 2,
    this.stackTrailingOnNarrow = false,
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
  final int? subtitleMaxLines;
  final bool stackTrailingOnNarrow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final effectiveOnTap = enabled ? onTap : null;
    final stackTrailing =
        stackTrailingOnNarrow &&
        trailing != null &&
        (MediaQuery.sizeOf(context).width < 400 ||
            MediaQuery.textScalerOf(context).scale(14) > 20);
    return Semantics(
      button: effectiveOnTap != null,
      selected: selected,
      label: semanticLabel ?? title,
      child: Material(
        color: selected
            ? accentColor.withValues(alpha: 0.16)
            : colors.surfaceContainerLow,
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
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: DTSpacing.xs),
                      Text(
                        subtitle,
                        maxLines: subtitleMaxLines,
                        overflow: subtitleMaxLines == null
                            ? TextOverflow.clip
                            : TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (stackTrailing)
                        Padding(
                          padding: const EdgeInsets.only(top: DTSpacing.sm),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: trailing,
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null && !stackTrailing) ...[
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
