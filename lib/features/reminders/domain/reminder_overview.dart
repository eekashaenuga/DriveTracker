import '../../documents/domain/vehicle_document.dart';
import '../../maintenance/domain/maintenance_reminder.dart';

class ReminderOverviewEntry {
  const ReminderOverviewEntry({this.maintenance, this.document});
  final MaintenanceReminder? maintenance;
  final DocumentExpiryReminder? document;
  MaintenanceReminderState get state => maintenance?.state ?? document!.state;
  int? get days => maintenance?.daysRemaining ?? document?.daysRemaining;
  String get name => maintenance?.item.name ?? document!.title;
}

List<ReminderOverviewEntry> orderReminderOverview(
  Iterable<MaintenanceReminder> maintenance,
  Iterable<DocumentExpiryReminder> documents,
) {
  final entries = [
    for (final m in maintenance.where((r) => r.shouldShowAsReminder))
      ReminderOverviewEntry(maintenance: m),
    for (final d in documents.where((r) => r.shouldShowAsReminder))
      ReminderOverviewEntry(document: d),
  ];
  entries.sort((a, b) {
    final severity = b.state.severity.compareTo(a.state.severity);
    if (severity != 0) return severity;
    // Compare calendar dates only; miles and days are different dimensions.
    final days = (a.days ?? (1 << 30)).compareTo(b.days ?? (1 << 30));
    if (days != 0) return days;
    return a.name.compareTo(b.name);
  });
  return entries;
}
