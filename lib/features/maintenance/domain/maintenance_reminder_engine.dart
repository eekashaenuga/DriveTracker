import '../../reminders/domain/date_reminder_schedule.dart';
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
    if (item.isExpiry) {
      final due = item.expiryDate;
      final days = due == null ? null : calendarDaysBetween(due, asOf);
      return MaintenanceReminder(
        item: item,
        state: days == null
            ? MaintenanceReminderState.setupNeeded
            : _stateForDays(days, warningThreshold: item.dateWarningDays),
        primaryBasis: due == null
            ? MaintenanceReminderBasis.none
            : MaintenanceReminderBasis.date,
        nextDateDue: due,
        daysRemaining: days,
        completions: completions,
      );
    }
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
        timeIntervalDays != null &&
        latestCompletion != null) {
      final baseline = _dateOnly(latestCompletion.eventDateTime);
      nextDateDue = DateTime(
        baseline.year,
        baseline.month,
        baseline.day + timeIntervalDays,
      );
      daysRemaining = calendarDaysBetween(nextDateDue, asOf);
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
    final missingBaseline =
        (item.mileageInterval != null && nextMileageDue == null) ||
        (item.timeIntervalDays != null && nextDateDue == null);
    final state =
        primaryBasis == MaintenanceReminderBasis.none ||
            (missingBaseline &&
                mileageState == MaintenanceReminderState.normal &&
                dateState == MaintenanceReminderState.normal)
        ? MaintenanceReminderState.setupNeeded
        : primaryBasis == MaintenanceReminderBasis.date
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
      // Dates and vehicle distance are different dimensions. Date-bearing
      // records form the first deterministic subgroup, then mileage-only items.
      final basisCompare = (a.nextDateDue == null ? 1 : 0).compareTo(
        b.nextDateDue == null ? 1 : 0,
      );
      if (basisCompare != 0) return basisCompare;
      final distanceCompare = a.nextDateDue != null && b.nextDateDue != null
          ? a.nextDateDue!.compareTo(b.nextDateDue!)
          : (a.milesRemaining ?? (1 << 62)).compareTo(
              b.milesRemaining ?? (1 << 62),
            );
      if (distanceCompare != 0) {
        return distanceCompare;
      }
      final name = a.item.name.compareTo(b.item.name);
      return name != 0 ? name : a.item.id.compareTo(b.item.id);
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

  DateTime _dateOnly(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}
