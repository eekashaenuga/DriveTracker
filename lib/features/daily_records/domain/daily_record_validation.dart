import '../../../core/utilities/validation_exception.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../../vehicles/domain/vehicle.dart';
import '../data/category_repository.dart';
import 'record_category.dart';

class DailyRecordValidation {
  const DailyRecordValidation._();

  static String? cleanOptional(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  static Future<Vehicle> requireActiveVehicle(
    VehicleRepository repository,
    String vehicleId,
  ) async {
    final vehicle = await repository.getById(vehicleId);
    if (vehicle == null) {
      throw const ValidationException(['Vehicle not found.']);
    }
    if (vehicle.isArchived) {
      throw const ValidationException([
        'Archived vehicles cannot receive new records.',
      ]);
    }
    return vehicle;
  }

  static Future<void> requireCategory({
    required CategoryRepository repository,
    required String categoryId,
    required RecordCategoryType type,
  }) async {
    final category = await repository.getById(categoryId);
    if (category == null || category.type != type) {
      throw ValidationException([
        'Select a ${type.label.toLowerCase()} category.',
      ]);
    }
    if (category.isArchived) {
      throw const ValidationException(['Archived categories cannot be used.']);
    }
  }

  static void requirePositiveMoney(int amountMinor, String label) {
    if (amountMinor <= 0) {
      throw ValidationException(['$label must be greater than zero.']);
    }
  }

  static void requireOptionalOdometer(int? odometer) {
    if (odometer != null && odometer < 0) {
      throw const ValidationException([
        'Odometer readings cannot be negative.',
      ]);
    }
  }
}
