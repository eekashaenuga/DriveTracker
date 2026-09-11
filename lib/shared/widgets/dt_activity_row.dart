import 'package:flutter/material.dart';

import '../../app/theme/dt_tokens.dart';
import 'dt_category_icon.dart';

class DTActivityRow extends StatelessWidget {
  const DTActivityRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.accentColor,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = accentColor ?? colors.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DTSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DTCategoryIcon(icon: icon, color: accent),
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
              constraints: const BoxConstraints(minWidth: 82, maxWidth: 124),
              child: Align(
                alignment: Alignment.centerRight,
                child: DefaultTextStyle.merge(
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                  child: trailing!,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
