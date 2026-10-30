import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/dt_tokens.dart';
import 'insight_formatters.dart';

class DTInsightCard extends StatelessWidget {
  const DTInsightCard({
    required this.child,
    this.padding = const EdgeInsets.all(DTSpacing.md),
    this.emphasized = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: emphasized ? colors.primaryContainer : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(padding: padding, child: child),
    );
  }
}

class DTInsightBarDatum {
  const DTInsightBarDatum({
    required this.index,
    required this.label,
    required this.value,
    required this.valueLabel,
    required this.semanticsLabel,
    required this.color,
    required this.selected,
    required this.onTap,
    this.components = const [],
  });

  final List<({int value, Color color})> components;
  final int index;
  final String label;
  final int value;
  final String valueLabel;
  final String semanticsLabel;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
}

class DTInsightBarChart extends StatelessWidget {
  const DTInsightBarChart({
    required this.bars,
    required this.maxValue,
    required this.barKeyPrefix,
    this.height = 148,
    super.key,
  });

  final List<DTInsightBarDatum> bars;
  final int maxValue;
  final String barKeyPrefix;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final slot = constraints.maxWidth / math.max(1, bars.length);
        final compressed =
            slot < MediaQuery.textScalerOf(context).scale(24) + 4;
        String shortLabel(String label) {
          final bits = label.split(' ');
          if (bits.length == 2 && RegExp(r'^\d{4}$').hasMatch(bits.last)) {
            return bits.first;
          }
          return label.split('-').first;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: Key('${barKeyPrefix}Viewport'),
              width: constraints.maxWidth,
              height: math.max(
                height,
                96 + MediaQuery.textScalerOf(context).scale(40),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final bar in bars)
                    Expanded(
                      child: _SelectableBar(
                        datum: bar,
                        maxValue: maxValue,
                        baselineColor: colors.outlineVariant.withValues(
                          alpha: 0.42,
                        ),
                        barKeyPrefix: barKeyPrefix,
                        interactive: slot >= 48,
                        showLabel: !compressed,
                        axisLabel: shortLabel(bar.label),
                      ),
                    ),
                ],
              ),
            ),
            if (compressed && bars.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        bars.first.label,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    if (bars.length > 2)
                      Expanded(
                        child: Text(
                          bars[bars.length ~/ 2].label,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        bars.last.label,
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SelectableBar extends StatelessWidget {
  const _SelectableBar({
    required this.datum,
    required this.maxValue,
    required this.baselineColor,
    required this.barKeyPrefix,
    required this.interactive,
    required this.showLabel,
    required this.axisLabel,
  });

  final bool interactive, showLabel;
  final String axisLabel;
  final DTInsightBarDatum datum;
  final int maxValue;
  final Color baselineColor;
  final String barKeyPrefix;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ratio = maxValue <= 0 || datum.value <= 0
        ? 0.0
        : (datum.value / maxValue).clamp(0.0, 1.0);
    final barHeight = datum.value <= 0 ? 0.0 : math.max(6.0, ratio * 96.0);
    final barColor = datum.selected ? colors.primary : datum.color;
    return Semantics(
      button: interactive,
      selected: datum.selected,
      label: datum.semanticsLabel,
      child: InkWell(
        key: Key('${barKeyPrefix}_${datum.index}'),
        borderRadius: BorderRadius.circular(DTRadii.card),
        onTap: interactive ? datum.onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    key: Key('${barKeyPrefix}Bar_${datum.index}'),
                    width: double.infinity,
                    height: barHeight,
                    child: datum.components.isEmpty
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              color: barColor,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(8),
                              ),
                            ),
                          )
                        : ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8),
                            ),
                            child: Column(
                              children: [
                                for (final component
                                    in datum.components.reversed)
                                  if (component.value > 0)
                                    Expanded(
                                      flex: component.value,
                                      child: ColoredBox(
                                        color: component.color,
                                        child: const SizedBox.expand(),
                                      ),
                                    ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
              Container(height: 1, color: baselineColor),
              const SizedBox(height: DTSpacing.xs),
              if (showLabel)
                Text(
                  axisLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: datum.selected
                        ? colors.primary
                        : colors.onSurfaceVariant,
                    fontWeight: datum.selected
                        ? FontWeight.w900
                        : FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class DTInsightLinePoint {
  const DTInsightLinePoint({
    required this.label,
    required this.value,
    required this.valueLabel,
    required this.detailLabel,
    required this.semanticsLabel,
    this.date,
    this.observationDetail,
  });

  final DateTime? date;
  final String? observationDetail;
  final String label;
  final double value;
  final String valueLabel;
  final String detailLabel;
  final String semanticsLabel;
}

class DTInsightLineChart extends StatefulWidget {
  const DTInsightLineChart({
    required this.points,
    required this.color,
    required this.pointKeyPrefix,
    required this.selectedDetailKey,
    this.height = 136,
    super.key,
  });

  final List<DTInsightLinePoint> points;
  final Color color;
  final String pointKeyPrefix;
  final Key selectedDetailKey;
  final double height;

  @override
  State<DTInsightLineChart> createState() => _DTInsightLineChartState();
}

class _DTInsightLineChartState extends State<DTInsightLineChart> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.points.isEmpty ? 0 : widget.points.length - 1;
  }

  @override
  void didUpdateWidget(covariant DTInsightLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.points.isEmpty) {
      _selectedIndex = 0;
      return;
    }
    if (_selectedIndex >= widget.points.length) {
      _selectedIndex = widget.points.length - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).colorScheme;
    final selected = widget.points[_selectedIndex];
    String dateLabel(DTInsightLinePoint p) =>
        p.date == null ? p.label : InsightFormat.date(p.date, compact: true);
    final minimum = widget.points.reduce((a, b) => a.value <= b.value ? a : b);
    final maximum = widget.points.reduce((a, b) => a.value >= b.value ? a : b);
    final minValue = widget.points
        .map((point) => point.value)
        .reduce((a, b) => a < b ? a : b);
    final maxValue = widget.points
        .map((point) => point.value)
        .reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Observed range: ${minimum.valueLabel} – ${maximum.valueLabel}'),
        LayoutBuilder(
          builder: (context, constraints) {
            final chartWidth = constraints.maxWidth;
            return SizedBox(
              width: chartWidth,
              height: widget.height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _LineChartPainter(
                        points: widget.points,
                        minValue: minValue,
                        maxValue: maxValue,
                        color: widget.color,
                        surfaceColor: colors.surfaceContainerHighest,
                        gridColor: colors.outlineVariant.withValues(
                          alpha: 0.32,
                        ),
                        selectedIndex: _selectedIndex,
                      ),
                    ),
                  ),
                  for (var index = 0; index < widget.points.length; index += 1)
                    _PointTapTarget(
                      tapKey: Key('${widget.pointKeyPrefix}_$index'),
                      index: index,
                      count: widget.points.length,
                      dateFraction: insightDateFraction(widget.points, index),
                      interactive: widget.points.length * 48 <= chartWidth,
                      point: widget.points[index],
                      chartWidth: chartWidth,
                      chartHeight: widget.height,
                      minValue: minValue,
                      maxValue: maxValue,
                      selected: index == _selectedIndex,
                      onTap: () => setState(() => _selectedIndex = index),
                    ),
                ],
              ),
            );
          },
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 24,
          children: [
            Text(dateLabel(widget.points.first)),
            Text(dateLabel(widget.points.last)),
          ],
        ),
        const SizedBox(height: DTSpacing.sm),
        Container(
          key: widget.selectedDetailKey,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: DTSpacing.md,
            vertical: DTSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.11),
            borderRadius: DTRadii.cardRadius,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selected.detailLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: DTSpacing.sm),
              Flexible(
                child: Text(
                  selected.valueLabel,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: widget.color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PointTapTarget extends StatelessWidget {
  const _PointTapTarget({
    required this.tapKey,
    required this.index,
    required this.count,
    required this.point,
    required this.dateFraction,
    required this.interactive,
    required this.chartWidth,
    required this.chartHeight,
    required this.minValue,
    required this.maxValue,
    required this.selected,
    required this.onTap,
  });

  final Key tapKey;
  final int index;
  final int count;
  final bool interactive;
  final double dateFraction;
  final DTInsightLinePoint point;
  final double chartWidth;
  final double chartHeight;
  final double minValue;
  final double maxValue;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final offset = _pointOffset(
      index: index,
      count: count,
      dateFraction: point.date == null ? null : dateFraction,
      value: point.value,
      chartWidth: chartWidth,
      chartHeight: chartHeight,
      minValue: minValue,
      maxValue: maxValue,
    );
    final maxLeft = math.max(0.0, chartWidth - 48);
    final maxTop = math.max(0.0, chartHeight - 48);
    return Positioned(
      left: (offset.dx - 24).clamp(0.0, maxLeft).toDouble(),
      top: (offset.dy - 24).clamp(0.0, maxTop).toDouble(),
      width: 48,
      height: 48,
      child: SizedBox.expand(
        key: tapKey,
        child: Semantics(
          button: interactive,
          selected: selected,
          label: point.semanticsLabel,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: interactive ? onTap : null,
          ),
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({
    required this.points,
    required this.minValue,
    required this.maxValue,
    required this.color,
    required this.surfaceColor,
    required this.gridColor,
    required this.selectedIndex,
  });

  final List<DTInsightLinePoint> points;
  final double minValue;
  final double maxValue;
  final Color color;
  final Color surfaceColor;
  final Color gridColor;
  final int selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final fraction in const [0.25, 0.5, 0.75]) {
      final y = size.height * fraction;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final offsets = [
      for (var index = 0; index < points.length; index += 1)
        _pointOffset(
          index: index,
          count: points.length,
          dateFraction: points[index].date == null
              ? null
              : insightDateFraction(points, index),
          value: points[index].value,
          chartWidth: size.width,
          chartHeight: size.height,
          minValue: minValue,
          maxValue: maxValue,
        ),
    ];

    for (var index = 0; index < offsets.length; index += 1) {
      final selected = index == selectedIndex;
      canvas.drawCircle(
        offsets[index],
        selected ? 7 : 5,
        Paint()
          ..color = selected ? color : surfaceColor
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        offsets[index],
        selected ? 7 : 5,
        Paint()
          ..color = color
          ..strokeWidth = selected ? 3 : 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.minValue != minValue ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.color != color ||
        oldDelegate.surfaceColor != surfaceColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}

Offset _pointOffset({
  required int index,
  required int count,
  required double value,
  double? dateFraction,
  required double chartWidth,
  required double chartHeight,
  required double minValue,
  required double maxValue,
}) {
  const horizontalPadding = 24.0;
  const verticalPadding = 16.0;
  final usableWidth = math.max(0.0, chartWidth - horizontalPadding * 2);
  final usableHeight = math.max(0.0, chartHeight - verticalPadding * 2);
  final denominator = math.max(1, count - 1);
  final x =
      horizontalPadding + usableWidth * (dateFraction ?? index / denominator);
  final spread = maxValue - minValue;
  final ratio = spread <= 0
      ? 0.5
      : ((value - minValue) / spread).clamp(0.0, 1.0).toDouble();
  final y = verticalPadding + usableHeight * (1 - ratio);
  return Offset(x, y);
}

/// Chronologically ordered observations use elapsed dates, never equal-index spacing.
/// Read the bounds in constant time so a chart does not repeatedly sort its history.
double insightDateFraction(List<DTInsightLinePoint> points, int index) {
  final first = points.firstOrNull?.date;
  final last = points.lastOrNull?.date;
  final at = points[index].date;
  if (at == null || first == null || last == null || first == last) return 0.5;
  return (at.difference(first).inMicroseconds /
          last.difference(first).inMicroseconds)
      .clamp(0.0, 1.0);
}
