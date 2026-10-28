import 'date_reminder_schedule.dart';
import '../../documents/domain/document_type.dart';

/// Shared by notifications and the details page. Days are evaluated at delivery,
/// not when the notification is created.
class ReminderWording {
  const ReminderWording._();
  static ({String title, String body}) message({
    required String vehicle,
    required String name,
    required DateTime due,
    required DateTime asOf,
    required bool expiry,
    bool mot = false,
  }) {
    final days = calendarDaysBetween(due, asOf);
    final when = days < 0
        ? (expiry ? 'expired' : 'overdue')
        : days == 0
        ? (expiry ? 'expires today' : 'due today')
        : '${expiry ? 'expires' : 'due'} in $days ${days == 1 ? 'day' : 'days'}';
    final title = '$name $when';
    if (DocumentType.classify(name) == DocumentType.tax) {
      return (
        title: title,
        body:
            '$vehicle: user-recorded vehicle tax due date ${formatDate(due)}. Review and update this record.',
      );
    }
    if (mot && days < 0) {
      // GOV.UK: https://www.gov.uk/getting-an-mot
      return (
        title: 'MOT expired',
        body:
            "Your $vehicle's MOT has expired. Driving without a valid MOT is generally illegal except in limited circumstances, such as travelling to a pre-arranged MOT test. Arrange an MOT before normal use.",
      );
    }
    if (mot) {
      return (
        title: title,
        body: days == 0
            ? 'Your $vehicle MOT expires today. Arrange a test before normal use continues.'
            : 'Your $vehicle MOT expires on ${formatDate(due)}. Arrange a test before it expires.',
      );
    }
    if (!expiry && days < 0 && name.toLowerCase().contains('oil')) {
      return (
        title: '$name service overdue',
        body:
            "Your $vehicle's $name service is overdue. Delaying oil service may increase engine wear and contribute to mechanical problems.",
      );
    }
    return (
      title: title,
      body:
          '$vehicle: $name ${days < 0 ? (expiry ? 'expired' : 'was due') : (expiry ? 'expires' : 'is due')} on ${formatDate(due)}. ${expiry ? 'Review and renew this record.' : 'Arrange the required maintenance.'}',
    );
  }

  static String formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
