import 'package:flutter/material.dart';

import '../../app/theme/dt_tokens.dart';

class DTFormSection extends StatelessWidget {
  const DTFormSection({
    required this.title,
    required this.children,
    this.icon,
    this.subtitle,
    super.key,
  });

  final String title;
  final IconData? icon;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: DTIconSizes.sm, color: colors.primary),
              const SizedBox(width: DTSpacing.sm),
            ],
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: DTSpacing.xs),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: DTSpacing.md),
        ...children,
      ],
    );
  }
}
