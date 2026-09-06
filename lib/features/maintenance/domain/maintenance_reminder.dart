import 'maintenance_item.dart';
import 'service_record.dart';

enum MaintenanceReminderState {
  normal('Normal'),
  upcoming('Upcoming'),
  dueSoon('Due soon'),
  due('Due'),
  overdue('Overdue');

  const MaintenanceReminderState(this.label);

  final String label;

  int get severity {
    return switch (this) {
      MaintenanceReminderState.normal => 0,
      MaintenanceReminderState.upcoming => 1,
      MaintenanceReminderState.dueSoon => 2,
      MaintenanceReminderState.due => 3,
      MaintenanceReminderState.overdue => 4,
    };
  }
}

enum MaintenanceReminderBasis { none, mileage, date }

class MaintenanceReminder {
  const MaintenanceReminder({
    required this.item,
    required this.state,
    required this.primaryBasis,
    required this.completions,
    this.latestCompletionDate,
    this.latestCompletionOdometer,
    this.nextMileageDue,
    this.nextDateDue,
    this.milesRemaining,
    this.daysRemaining,
  });

  final MaintenanceItem item;
  final MaintenanceReminderState state;
  final MaintenanceReminderBasis primaryBasis;
  final DateTime? latestCompletionDate;
  final int? latestCompletionOdometer;
  final int? nextMileageDue;
  final DateTime? nextDateDue;
  final int? milesRemaining;
  final int? daysRemaining;
  final List<MaintenanceCompletion> completions;

  bool get shouldShowAsReminder {
    return item.reminderEnabled && item.hasInterval && !item.isArchived;
  }
}
