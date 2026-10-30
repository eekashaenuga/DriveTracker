import '../../../core/calculations/analytics_date_range.dart';
import 'insight_formatters.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

enum InsightTone { teal, warm, rose, neutral, mint }

({Color surface, Color ink, Color accent}) insightPalette(
  BuildContext context,
  InsightTone tone,
) {
  final c = Theme.of(context).colorScheme;
  return switch (tone) {
    InsightTone.teal => (
      surface: c.primaryContainer,
      ink: c.onPrimaryContainer,
      accent: c.primary,
    ),
    InsightTone.warm => (
      surface: c.tertiaryContainer,
      ink: c.onTertiaryContainer,
      accent: c.tertiary,
    ),
    InsightTone.rose => (
      surface: c.errorContainer,
      ink: c.onErrorContainer,
      accent: c.error,
    ),
    InsightTone.neutral => (
      surface: c.surfaceContainer,
      ink: c.onSurface,
      accent: c.onSurfaceVariant,
    ),
    InsightTone.mint => (
      surface: c.secondaryContainer,
      ink: c.onSecondaryContainer,
      accent: c.secondary,
    ),
  };
}

/// Uses persisted identity, so renaming/reordering a category keeps its accent.
Color insightCategoryAccent(BuildContext context, String categoryId) {
  var hash = 2166136261;
  for (final code in categoryId.codeUnits) {
    hash = ((hash ^ code) * 16777619) & 0xffffffff;
  }
  final c = Theme.of(context).colorScheme;
  final palette = [
    c.secondary,
    c.tertiary,
    Color.lerp(c.primary, c.onSurfaceVariant, 0.45)!,
    c.onSurfaceVariant,
  ];
  return palette[hash % palette.length];
}

class InsightMetricTile extends StatelessWidget {
  const InsightMetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
    this.tone = InsightTone.teal,
    this.hero = false,
    this.labelHeight,
    this.valueHeight,
    super.key,
  });
  final String label, value;
  final String? caption;
  final IconData icon;
  final InsightTone tone;
  final bool hero;
  final double? labelHeight, valueHeight;

  InsightMetricTile aligned(double labelHeight, double valueHeight) =>
      InsightMetricTile(
        key: key,
        label: label,
        value: value,
        icon: icon,
        caption: caption,
        tone: tone,
        hero: hero,
        labelHeight: labelHeight,
        valueHeight: valueHeight,
      );
  @override
  Widget build(BuildContext context) {
    final p = insightPalette(context, tone);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: ExcludeSemantics(
                  child: Icon(icon, size: 22, color: p.ink),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: labelHeight,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: p.ink),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: valueHeight,
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontSize: hero ? 32 : 26,
                    fontWeight: FontWeight.w700,
                    color: p.ink,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: 8),
                Text(
                  caption!,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: p.ink),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class InsightMetricGrid extends StatelessWidget {
  const InsightMetricGrid({
    required this.tiles,
    this.maxColumns = 3,
    this.alignRows = false,
    super.key,
  });
  final List<InsightMetricTile> tiles;
  final int maxColumns;
  final bool alignRows;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context);
      var minimum = scale.scale(130);
      for (final tile in tiles) {
        // Keep indivisible amounts readable; allow short phrases/units to wrap.
        for (final word in tile.value.split(' ')) {
          final painter = TextPainter(
            text: TextSpan(
              text: word,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontSize: tile.hero ? 32 : 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
              ),
            ),
            textDirection: Directionality.of(context),
            textScaler: scale,
          )..layout();
          minimum = math.max(minimum, painter.width + 36);
          painter.dispose();
        }
      }
      final columns = ((constraints.maxWidth + 12) / (minimum + 12))
          .floor()
          .clamp(1, maxColumns);
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      if (alignRows) {
        double height(String text, TextStyle? style) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: Directionality.of(context),
            textScaler: scale,
          )..layout(maxWidth: math.max(1, width - 36));
          final result = painter.height;
          painter.dispose();
          return result;
        }

        return Column(
          children: [
            for (var start = 0; start < tiles.length; start += columns)
              Padding(
                padding: EdgeInsets.only(top: start == 0 ? 0 : 12),
                child: Builder(
                  builder: (context) {
                    final row = tiles.skip(start).take(columns).toList();
                    final labelHeight = row
                        .map(
                          (t) => height(
                            t.label,
                            Theme.of(context).textTheme.labelLarge,
                          ),
                        )
                        .reduce(math.max);
                    final valueHeight = row
                        .map(
                          (t) => height(
                            t.value,
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontSize: t.hero ? 32 : 26,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.6,
                            ),
                          ),
                        )
                        .reduce(math.max);
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var index = 0; index < columns; index++) ...[
                            if (index > 0) const SizedBox(width: 12),
                            Expanded(
                              child: index < row.length
                                  ? row[index].aligned(labelHeight, valueHeight)
                                  : const SizedBox(),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      }
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final tile in tiles) SizedBox(width: width, child: tile),
        ],
      );
    },
  );
}

class InsightNavigationCard extends StatelessWidget {
  const InsightNavigationCard({
    required this.title,
    required this.value,
    required this.period,
    required this.summary,
    required this.icon,
    required this.onTap,
    this.tone = InsightTone.teal,
    super.key,
  });
  final String title, value, period, summary;
  final IconData icon;
  final VoidCallback onTap;
  final InsightTone tone;
  @override
  Widget build(BuildContext context) {
    final p = insightPalette(context, tone);
    final c = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: c.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: c.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: p.ink),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      period,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: c.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      summary,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: c.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const ExcludeSemantics(child: Icon(Icons.chevron_right)),
            ],
          ),
        ),
      ),
    );
  }
}

class InsightSectionTitle extends StatelessWidget {
  const InsightSectionTitle(
    this.title, {
    this.action,
    this.onAction,
    super.key,
  });
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

class InsightRankedRow extends StatelessWidget {
  const InsightRankedRow({
    required this.label,
    required this.value,
    required this.fraction,
    this.share,
    this.tone = InsightTone.teal,
    this.onTap,
    this.accent,
    super.key,
  });
  final String label, value;
  final String? share;
  final double fraction;
  final InsightTone tone;
  final VoidCallback? onTap;
  final Color? accent;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final p = insightPalette(context, tone);
    final labelText = Text(
      label,
      style: Theme.of(context).textTheme.bodyLarge
          ?.copyWith(fontWeight: FontWeight.w500),
    );
    final amount = Text(
      value,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w700),
    );
    return Semantics(
      button: onTap != null,
      label: '$label, $value${share == null ? '' : ', $share'}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (MediaQuery.textScalerOf(context).scale(14) > 21) ...[
                labelText,
                amount,
              ] else
                Row(
                  children: [
                    Expanded(child: labelText),
                    const SizedBox(width: 12),
                    amount,
                    if (onTap != null)
                      const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              const SizedBox(height: 10),
              ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 7,
                    color: c.surfaceContainerHighest,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: fraction.clamp(0.0, 1.0),
                      child: ColoredBox(
                        color: accent ?? p.accent,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
              if (share != null) ...[
                const SizedBox(height: 5),
                Text(
                  share!,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: c.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showInsightInformation(
  BuildContext context,
  String title,
  String message,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: SingleChildScrollView(child: Text(message)),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  ),
);

String insightPeriodLabel(AnalyticsDateRange range) => switch (range.preset) {
  AnalyticsRangePreset.week => 'This week',
  AnalyticsRangePreset.month => 'This month',
  AnalyticsRangePreset.lastMonth => 'Last month',
  AnalyticsRangePreset.lastThreeMonths => 'Last 3 months',
  AnalyticsRangePreset.year => 'This year',
  AnalyticsRangePreset.all => 'All time',
  AnalyticsRangePreset.custom => InsightFormat.customRange(range),
};
