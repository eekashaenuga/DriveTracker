import '../../../core/utilities/validation_exception.dart';
import 'vehicle_draft.dart';

class VehicleValidator {
  const VehicleValidator._();

  static List<String> validate(
    VehicleDraft draft, {
    required bool requireInitialOdometer,
  }) {
    final errors = <String>[];

    if (cleanRequired(draft.name).isEmpty) {
      errors.add('Vehicle name is required.');
    }
    if (cleanRequired(draft.make).isEmpty) {
      errors.add('Make is required.');
    }
    if (cleanRequired(draft.model).isEmpty) {
      errors.add('Model is required.');
    }

    if (requireInitialOdometer) {
      final odometer = draft.currentOdometer;
      if (odometer == null) {
        errors.add('Current odometer is required.');
      } else if (odometer < 0) {
        errors.add('Current odometer cannot be negative.');
      }
    }

    final year = draft.year;
    if (year != null) {
      final maxYear = DateTime.now().year + 1;
      if (year < 1886 || year > maxYear) {
        errors.add('Year must be between 1886 and $maxYear.');
      }
    }

    final purchaseMileage = draft.purchaseMileage;
    if (purchaseMileage != null && purchaseMileage < 0) {
      errors.add('Purchase mileage cannot be negative.');
    }

    final purchasePrice = draft.purchasePrice;
    if (purchasePrice != null && purchasePrice < 0) {
      errors.add('Purchase price cannot be negative.');
    }

    return errors;
  }

  static void throwIfInvalid(
    VehicleDraft draft, {
    required bool requireInitialOdometer,
  }) {
    final errors = validate(
      draft,
      requireInitialOdometer: requireInitialOdometer,
    );
    if (errors.isNotEmpty) {
      throw ValidationException(errors);
    }
  }

  static String cleanRequired(String value) => value.trim();

  static String? cleanOptional(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
