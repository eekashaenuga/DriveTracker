import '../../documents/domain/vehicle_document.dart';
import '../../documents/domain/document_type.dart';
import '../../maintenance/domain/maintenance_reminder.dart';

class ReminderOverviewEntry {
  const ReminderOverviewEntry({
    this.maintenance,
    this.document,
    this.motSources = const [],
  });
  final MaintenanceReminder? maintenance;
  final DocumentExpiryReminder? document;
  final List<ReminderOverviewEntry> motSources;
  String get vehicleId =>
      maintenance?.item.vehicleId ??
      document?.document.vehicleId ??
      motSources.first.vehicleId;
  String get stableKey => isMotReview
      ? 'mot_review_$vehicleId'
      : maintenance?.item.id ?? document!.document.id;
  DateTime? get dueDate {
    if (!isMotReview) {
      return maintenance?.nextDateDue ?? document?.document.expiryDate;
    }
    final dates =
        motSources.map((s) => s.dueDate).whereType<DateTime>().toList()..sort();
    return dates.firstOrNull;
  }

  int? get remainingDistance => maintenance?.milesRemaining;
  int get sectionOrder => state == MaintenanceReminderState.overdue
      ? 0
      : state == MaintenanceReminderState.due
      ? 1
      : isMotReview || state == MaintenanceReminderState.setupNeeded
      ? 3
      : state == MaintenanceReminderState.dueSoon
      ? 2
      : 4;
  bool get isMotReview => motSources.isNotEmpty;
  bool get isMotSource =>
      document?.document.type == DocumentType.mot ||
      (maintenance != null &&
          DocumentType.classify(
                maintenance!.item.category ?? maintenance!.item.name,
              ) ==
              DocumentType.mot);
  MaintenanceReminderState get state => isMotReview
      ? motSources
            .map((s) => s.state)
            .reduce((a, b) => a.severity >= b.severity ? a : b)
      : maintenance?.state ?? document!.state;
  int? get days => isMotReview
      ? null
      : maintenance?.daysRemaining ?? document?.daysRemaining;
  String get name => isMotReview
      ? 'MOT - review sources'
      : maintenance?.item.name ?? document!.title;
  String get sectionTitle => switch (sectionOrder) {
    0 => 'Overdue',
    1 => 'Due today / Due now',
    2 => 'Due soon',
    3 => 'Review / Setup needed',
    _ => 'Upcoming',
  };
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
  // Group only inside each vehicle. Different vehicles never share a source group.
  for (final vehicle in entries.map((e) => e.vehicleId).toSet()) {
    final sources = entries
        .where((e) => e.vehicleId == vehicle && e.isMotSource)
        .toList();
    if (sources.length > 1) {
      entries.removeWhere((e) => sources.contains(e));
      entries.add(ReminderOverviewEntry(motSources: sources));
    }
  }
  entries.sort((a, b) {
    final section = a.sectionOrder.compareTo(b.sectionOrder);
    if (section != 0) return section;
    final basis = (a.dueDate == null ? 1 : 0).compareTo(
      b.dueDate == null ? 1 : 0,
    );
    if (basis != 0) return basis;
    final due = a.dueDate != null && b.dueDate != null
        ? a.dueDate!.compareTo(b.dueDate!)
        : a.vehicleId == b.vehicleId
        ? (a.remainingDistance ?? (1 << 62)).compareTo(
            b.remainingDistance ?? (1 << 62),
          )
        : 0;
    if (due != 0) return due;
    final vehicle = a.vehicleId.compareTo(b.vehicleId);
    if (vehicle != 0) return vehicle;
    final name = a.name.compareTo(b.name);
    return name != 0 ? name : a.stableKey.compareTo(b.stableKey);
  });
  return entries;
}
