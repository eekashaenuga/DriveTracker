import 'package:flutter/material.dart';

import '../../../core/utilities/formatters.dart';
import '../../insights/presentation/insight_formatters.dart';
import '../domain/daily_activity.dart';

class HistoryRecordRow extends StatelessWidget {
  const HistoryRecordRow({
    required this.record,
    required this.showVehicle,
    required this.onTap,
    super.key,
  });
  final DailyActivity record;
  final bool showVehicle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = switch (record.type) {
      DailyActivityType.refuel => Icons.local_gas_station_outlined,
      DailyActivityType.service => Icons.build_outlined,
      DailyActivityType.expense => Icons.payments_outlined,
      DailyActivityType.income => Icons.work_outline,
      _ => Icons.speed,
    };
    final local = record.eventDateTime.toLocal();
    final date =
        '${InsightFormat.date(local)} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    final secondary = [
      date,
      if (showVehicle) record.vehicleName ?? 'Vehicle unavailable',
      record.subtitle,
      if (record.odometer != null && record.vehicleDistanceUnit != null)
        DTFormatters.odometer(record.odometer, record.vehicleDistanceUnit!),
    ].join(' · ');
    return Semantics(
      button: true,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(record.title, style: theme.textTheme.titleSmall),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(secondary),
            if (record.amountMinor != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  DTFormatters.moneyMinor(record.amountMinor!),
                  style: theme.textTheme.titleMedium,
                ),
              ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
