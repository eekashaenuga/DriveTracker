import '../../maintenance/domain/maintenance_item.dart';
import '../../reminders/domain/date_reminder_schedule.dart';
import 'document_type.dart';
import 'vehicle_document.dart';

class VehicleDocumentOverview {
  VehicleDocumentOverview({
    required String vehicleId,
    required Iterable<VehicleDocument> documents,
    required Iterable<MaintenanceItem> maintenance,
  }) : documents = documents
           .where((d) => d.vehicleId == vehicleId && !d.isArchived)
           .toList(),
       motItems = maintenance
           .where(
             (m) =>
                 m.vehicleId == vehicleId &&
                 !m.isArchived &&
                 DocumentType.classify(m.category ?? m.name) ==
                     DocumentType.mot,
           )
           .toList();

  final List<VehicleDocument> documents;
  final List<MaintenanceItem> motItems;
  List<VehicleDocument> forType(DocumentType type) =>
      documents.where((d) => d.type == type).toList();
  int get motSourceCount => forType(DocumentType.mot).length + motItems.length;
  bool get motNeedsReview => motSourceCount > 1;
}

String documentStatusLabel(DocumentType type, DateTime? date, DateTime asOf) {
  if (date == null) return type.requiresDate ? 'Setup needed' : 'Recorded';
  final days = calendarDaysBetween(date, asOf);
  if (type == DocumentType.tax) {
    if (days < 0) return 'Overdue';
    if (days == 0) return 'Due';
    return days <= DocumentExpiryReminder.expiringSoonDays
        ? 'Due soon'
        : 'Due later';
  }
  if (days < 0) return 'Expired';
  return days <= DocumentExpiryReminder.expiringSoonDays
      ? 'Expiring soon'
      : 'Valid';
}
