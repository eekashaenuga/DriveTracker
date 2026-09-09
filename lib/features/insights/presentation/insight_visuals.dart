import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/dt_tokens.dart';

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
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: emphasized
            ? colors.primaryContainer.withValues(alpha: 0.32)
            : colors.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colors.outlineVariant.withValues(
            alpha: emphasized ? 0.28 : 0.2,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
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
  });

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
        final chartWidth = math.max(constraints.maxWidth, bars.length * 54.0);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: chartWidth,
            height: height,
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
                    ),
                  ),
              ],
            ),
          ),
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
  });

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
      button: true,
      selected: datum.selected,
      label: datum.semanticsLabel,
      child: InkWell(
        key: Key('${barKeyPrefix}_${datum.index}'),
        borderRadius: BorderRadius.circular(DTRadii.card),
        onTap: datum.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DTSpacing.xs),
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
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Container(height: 1, color: baselineColor),
              const SizedBox(height: DTSpacing.xs),
              Text(
                datum.label,
                maxLines: 1,
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
  });

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
    final minValue = widget.points
        .map((point) => point.value)
        .reduce((a, b) => a < b ? a : b);
    final maxValue = widget.points
        .map((point) => point.value)
        .reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final chartWidth = math.max(
              constraints.maxWidth,
              math.max(1, widget.points.length) * 64.0,
            );
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
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
                    for (
                      var index = 0;
                      index < widget.points.length;
                      index += 1
                    )
                      _PointTapTarget(
                        tapKey: Key('${widget.pointKeyPrefix}_$index'),
                        index: index,
                        count: widget.points.length,
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
              ),
            );
          },
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: DTSpacing.sm),
              Text(
                selected.valueLabel,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: widget.color,
                  fontWeight: FontWeight.w900,
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
          button: true,
          selected: selected,
          label: point.semanticsLabel,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onTap,
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
          value: points[index].value,
          chartWidth: size.width,
          chartHeight: size.height,
          minValue: minValue,
          maxValue: maxValue,
        ),
    ];

    if (offsets.length > 1) {
      final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (final offset in offsets.skip(1)) {
        path.lineTo(offset.dx, offset.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

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
  final x = horizontalPadding + usableWidth * index / denominator;
  final spread = maxValue - minValue;
  final ratio = spread <= 0
      ? 0.5
      : ((value - minValue) / spread).clamp(0.0, 1.0).toDouble();
  final y = verticalPadding + usableHeight * (1 - ratio);
  return Offset(x, y);
}
