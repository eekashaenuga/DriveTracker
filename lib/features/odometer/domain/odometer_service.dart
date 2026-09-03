import '../../../core/utilities/id_generator.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../data/odometer_repository.dart';
import 'odometer_entry.dart';
import 'odometer_policy.dart';

typedef Clock = DateTime Function();

class OdometerService {
  OdometerService({
    required this.vehicleRepository,
    required this.odometerRepository,
    this.policy = const OdometerPolicy(),
    IdGenerator? idGenerator,
    Clock? clock,
  }) : _idGenerator = idGenerator ?? IdGenerator(),
       _clock = clock ?? (() => DateTime.now().toUtc());

  final VehicleRepository vehicleRepository;
  final OdometerRepository odometerRepository;
  final OdometerPolicy policy;
  final IdGenerator _idGenerator;
  final Clock _clock;

  OdometerAssessment assessManualReading({
    required int? currentOdometer,
    required int newOdometer,
  }) {
    return policy.assess(
      currentOdometer: currentOdometer,
      newOdometer: newOdometer,
    );
  }

  Future<OdometerEntry> recordManualReading({
    required String vehicleId,
    required int odometer,
    DateTime? eventDateTime,
    bool allowHistorical = false,
    bool confirmLargeIncrease = false,
  }) async {
    final vehicle = await vehicleRepository.getById(vehicleId);
    if (vehicle == null) {
      throw const ValidationException(['Vehicle not found.']);
    }
    if (vehicle.isArchived) {
      throw const ValidationException([
        'Archived vehicles cannot receive new odometer readings.',
      ]);
    }

    final current = await odometerRepository.currentOdometerForVehicle(
      vehicleId,
    );
    final assessment = assessManualReading(
      currentOdometer: current,
      newOdometer: odometer,
    );

    switch (assessment.decision) {
      case OdometerDecision.invalid:
        throw ValidationException([assessment.message]);
      case OdometerDecision.belowCurrent:
        if (!allowHistorical) {
          throw OdometerConfirmationRequired(assessment);
        }
        break;
      case OdometerDecision.unusuallyLargeIncrease:
        if (!confirmLargeIncrease) {
          throw OdometerConfirmationRequired(assessment);
        }
        break;
      case OdometerDecision.accepted:
        break;
    }

    final now = _clock().toUtc();
    final entry = OdometerEntry(
      id: _idGenerator.newId('odo'),
      vehicleId: vehicleId,
      odometer: odometer,
      eventDateTime: (eventDateTime ?? now).toUtc(),
      sourceType: OdometerSourceType.manual,
      createdAt: now,
      updatedAt: now,
    );
    await odometerRepository.insert(entry);
    return entry;
  }
}
