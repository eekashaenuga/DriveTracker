import 'package:flutter/material.dart';

import '../../../app/theme/dt_motion.dart';
import 'insight_formatters.dart';
import 'insight_visuals.dart';

/// Text alternatives to the unchanged chart observations, newest first.
class InsightRecordedValues extends StatelessWidget {
  const InsightRecordedValues({
    required this.points,
    required this.kind,
    super.key,
  });

  final List<DTInsightLinePoint> points;
  final String kind;

  @override
  Widget build(BuildContext context) {
    final latest = points.reversed.toList(growable: false);
    return ExpansionTile(
      key: PageStorageKey('fuelValues_$kind'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 4),
      expansionAnimationStyle: DTMotion.reduceMotionOf(context)
          ? AnimationStyle.noAnimation
          : null,
      title: const Text('Recorded values'),
      children: [
        for (final point in latest.take(5))
          _ObservationRow(point: point, preview: true),
        TextButton(
          key: const Key('insightsAllRecordedValuesButton'),
          onPressed: () {
            final page = _AllRecordedValues(points: latest, kind: kind);
            Navigator.of(context).push<void>(
              DTMotion.reduceMotionOf(context)
                  ? PageRouteBuilder<void>(
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                      pageBuilder: (_, _, _) => page,
                    )
                  : MaterialPageRoute<void>(builder: (_) => page),
            );
          },
          child: const Text('View all recorded values'),
        ),
      ],
    );
  }
}

class _AllRecordedValues extends StatelessWidget {
  const _AllRecordedValues({required this.points, required this.kind});
  final List<DTInsightLinePoint> points;
  final String kind;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('insightsAllRecordedValues'),
    appBar: AppBar(title: Text('$kind recorded values')),
    body: SafeArea(
      top: false,
      child: ListView.builder(
        key: const Key('insightsAllRecordedValuesList'),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        itemCount: points.length,
        itemBuilder: (_, index) => _ObservationRow(point: points[index]),
      ),
    ),
  );
}

class _ObservationRow extends StatelessWidget {
  const _ObservationRow({required this.point, this.preview = false});
  final DTInsightLinePoint point;
  final bool preview;

  @override
  Widget build(BuildContext context) => Semantics(
    key: preview ? const Key('insightsRecordedValuePreviewRow') : null,
    label:
        '${point.semanticsLabel}${point.observationDetail == null ? '' : ', ${point.observationDetail}'}',
    excludeSemantics: true,
    child: Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 4,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: Text(
                    point.date == null
                        ? point.label
                        : InsightFormat.date(point.date),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: Text(
                    point.valueLabel,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
          if (point.observationDetail != null)
            Text(
              point.observationDetail!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    ),
  );
}
