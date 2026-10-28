import '../../../core/database/app_database.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../reminders/domain/date_reminder_schedule.dart';
import 'document_type.dart';

bool hasDateNotifications(DateReminderSchedule? schedule) =>
    schedule == null ||
    schedule.offsets.isNotEmpty ||
    schedule.dailyFromDays != null;

/// Checks both existing storage models without choosing an authoritative date.
Future<void> ensureNoOtherMotReminder(
  AppDatabase database,
  String vehicleId, {
  String? excludingDocumentId,
  String? excludingMaintenanceId,
}) async {
  final db = await database.database;
  final documents = await db.query(
    'documents',
    where: 'vehicle_id = ? AND is_archived = 0 AND expiry_date IS NOT NULL',
    whereArgs: [vehicleId],
  );
  final maintenance = await db.query(
    'maintenance_items',
    where: 'vehicle_id = ? AND is_archived = 0 AND reminder_enabled = 1',
    whereArgs: [vehicleId],
  );
  final duplicate =
      documents.any(
        (d) =>
            d['id'] != excludingDocumentId &&
            DocumentType.classify(d['category'] as String) ==
                DocumentType.mot &&
            hasDateNotifications(
              DateReminderSchedule.fromJson(d['reminder_schedule']),
            ),
      ) ||
      maintenance.any(
        (m) =>
            m['id'] != excludingMaintenanceId &&
            DocumentType.classify((m['category'] ?? m['name']) as String) ==
                DocumentType.mot &&
            (m['record_kind'] == 'scheduled' ||
                hasDateNotifications(
                  DateReminderSchedule.fromJson(m['reminder_schedule']),
                )),
      );
  if (duplicate) {
    throw const ValidationException([
      'Another active MOT reminder exists. Review Documents & Compliance and disable or archive the redundant reminder, or save this document with no date notifications.',
    ]);
  }
}
