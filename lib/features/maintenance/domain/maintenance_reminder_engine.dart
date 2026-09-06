import 'maintenance_item.dart';
import 'maintenance_reminder.dart';
import 'service_record.dart';

class MaintenanceReminderEngine {
  const MaintenanceReminderEngine();

  static const dueSoonMileageThreshold = 300;
  static const defaultMileageWarning = 1000;
  static const dueSoonDateThresholdDays = 7;
  static const defaultDateWarningDays = 30;

  MaintenanceReminder evaluate({
    required MaintenanceItem item,
    required List<MaintenanceCompletion> completions,
    required int? currentOdometer,
    required DateTime asOf,
  }) {
    final sortedCompletions = [...completions]..sort(_compareCompletions);
    final latestCompletion = sortedCompletions.isEmpty
        ? null
        : sortedCompletions.first;
    MaintenanceCompletion? latestMileageCompletion;
    for (final completion in sortedCompletions) {
      if (completion.odometer != null) {
        latestMileageCompletion = completion;
        break;
      }
    }

    int? nextMileageDue;
    int? milesRemaining;
    var mileageState = MaintenanceReminderState.normal;
    final mileageInterval = item.mileageInterval;
    final latestOdometer = latestMileageCompletion?.odometer;
    if (!item.isArchived &&
        item.reminderEnabled &&
        mileageInterval != null &&
        latestOdometer != null &&
        currentOdometer != null) {
      nextMileageDue = latestOdometer + mileageInterval;
      milesRemaining = nextMileageDue - currentOdometer;
      mileageState = _stateForMileage(
        milesRemaining,
        warningThreshold: item.mileageWarning,
      );
    }

    DateTime? nextDateDue;
    int? daysRemaining;
    var dateState = MaintenanceReminderState.normal;
    final timeIntervalDays = item.timeIntervalDays;
    if (!item.isArchived &&
        item.reminderEnabled &&
        timeIntervalDays != null &&
        latestCompletion != null) {
      nextDateDue = _dateOnly(latestCompletion.eventDateTime)
          .add(Duration(days: timeIntervalDays));
      daysRemaining = nextDateDue.difference(_dateOnly(asOf)).inDays;
      dateState = _stateForDays(
        daysRemaining,
        warningThreshold: item.dateWarningDays,
      );
    }

    final primaryBasis = _primaryBasis(
      mileageState: mileageState,
      dateState: dateState,
      milesRemaining: milesRemaining,
      daysRemaining: daysRemaining,
    );
    final state = primaryBasis == MaintenanceReminderBasis.date
        ? dateState
        : mileageState.severity >= dateState.severity
        ? mileageState
        : dateState;

    return MaintenanceReminder(
      item: item,
      state: state,
      primaryBasis: primaryBasis,
      latestCompletionDate: latestCompletion?.eventDateTime,
      latestCompletionOdometer: latestOdometer,
      nextMileageDue: nextMileageDue,
      nextDateDue: nextDateDue,
      milesRemaining: milesRemaining,
      daysRemaining: daysRemaining,
      completions: sortedCompletions,
    );
  }

  List<MaintenanceReminder> sortByUrgency(
    Iterable<MaintenanceReminder> reminders,
  ) {
    final sorted = [...reminders];
    sorted.sort((a, b) {
      final stateCompare = b.state.severity.compareTo(a.state.severity);
      if (stateCompare != 0) {
        return stateCompare;
      }
      final aDistance = _closestPositive(a.milesRemaining, a.daysRemaining);
      final bDistance = _closestPositive(b.milesRemaining, b.daysRemaining);
      final distanceCompare = aDistance.compareTo(bDistance);
      if (distanceCompare != 0) {
        return distanceCompare;
      }
      return a.item.name.compareTo(b.item.name);
    });
    return sorted;
  }

  MaintenanceReminder? mostUrgent(Iterable<MaintenanceReminder> reminders) {
    final visible = reminders.where(
      (reminder) => reminder.shouldShowAsReminder,
    );
    final sorted = sortByUrgency(visible);
    return sorted.isEmpty ? null : sorted.first;
  }

  MaintenanceReminderState _stateForMileage(
    int remaining, {
    required int warningThreshold,
  }) {
    if (remaining < 0) {
      return MaintenanceReminderState.overdue;
    }
    if (remaining == 0) {
      return MaintenanceReminderState.due;
    }
    if (remaining <= dueSoonMileageThreshold) {
      return MaintenanceReminderState.dueSoon;
    }
    if (remaining <= warningThreshold) {
      return MaintenanceReminderState.upcoming;
    }
    return MaintenanceReminderState.normal;
  }

  MaintenanceReminderState _stateForDays(
    int remaining, {
    required int warningThreshold,
  }) {
    if (remaining < 0) {
      return MaintenanceReminderState.overdue;
    }
    if (remaining == 0) {
      return MaintenanceReminderState.due;
    }
    if (remaining <= dueSoonDateThresholdDays) {
      return MaintenanceReminderState.dueSoon;
    }
    if (remaining <= warningThreshold) {
      return MaintenanceReminderState.upcoming;
    }
    return MaintenanceReminderState.normal;
  }

  MaintenanceReminderBasis _primaryBasis({
    required MaintenanceReminderState mileageState,
    required MaintenanceReminderState dateState,
    required int? milesRemaining,
    required int? daysRemaining,
  }) {
    if (milesRemaining == null && daysRemaining == null) {
      return MaintenanceReminderBasis.none;
    }
    if (milesRemaining == null) {
      return MaintenanceReminderBasis.date;
    }
    if (daysRemaining == null) {
      return MaintenanceReminderBasis.mileage;
    }
    if (dateState.severity > mileageState.severity) {
      return MaintenanceReminderBasis.date;
    }
    return MaintenanceReminderBasis.mileage;
  }

  int _compareCompletions(MaintenanceCompletion a, MaintenanceCompletion b) {
    final eventCompare = b.eventDateTime.compareTo(a.eventDateTime);
    if (eventCompare != 0) {
      return eventCompare;
    }
    return b.createdAt.compareTo(a.createdAt);
  }

  int _closestPositive(int? miles, int? days) {
    final values = [?miles, ?days];
    if (values.isEmpty) {
      return 1 << 30;
    }
    values.sort();
    return values.first;
  }

  DateTime _dateOnly(DateTime value) {
    final utc = value.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }
}
