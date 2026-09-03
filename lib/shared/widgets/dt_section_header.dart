import 'package:flutter/material.dart';

import '../../app/theme/dt_tokens.dart';

class DTSectionHeader extends StatelessWidget {
  const DTSectionHeader({required this.title, this.action, super.key});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: DTSpacing.xl, bottom: DTSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
