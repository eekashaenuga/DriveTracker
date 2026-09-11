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

  Future<OdometerEntry> updateManualReading({
    required String entryId,
    required int odometer,
    required DateTime eventDateTime,
    bool confirmUnusualSequence = false,
  }) async {
    if (odometer < 0) {
      throw const ValidationException([
        'Odometer readings cannot be negative.',
      ]);
    }

    final existing = await odometerRepository.getById(entryId);
    if (existing == null) {
      throw const ValidationException(['Odometer reading not found.']);
    }
    if (existing.sourceType != OdometerSourceType.manual) {
      throw const ValidationException([
        'Only manual odometer readings can be edited from History.',
      ]);
    }

    final vehicle = await vehicleRepository.getById(existing.vehicleId);
    if (vehicle == null) {
      throw const ValidationException(['Vehicle not found.']);
    }

    final now = _clock().toUtc();
    final updated = OdometerEntry(
      id: existing.id,
      vehicleId: existing.vehicleId,
      odometer: odometer,
      eventDateTime: eventDateTime.toUtc(),
      sourceType: existing.sourceType,
      sourceRecordId: existing.sourceRecordId,
      createdAt: existing.createdAt,
      updatedAt: now,
    );

    final entries = await odometerRepository.allForVehicle(existing.vehicleId);
    if (!confirmUnusualSequence &&
        _isUnusualForChronologicalNeighbors(entries, updated)) {
      throw const OdometerEditConfirmationRequired(
        'This reading does not fit the surrounding odometer history. Save it anyway?',
      );
    }

    await odometerRepository.update(updated);
    return updated;
  }

  bool _isUnusualForChronologicalNeighbors(
    List<OdometerEntry> entries,
    OdometerEntry edited,
  ) {
    final chronological = [
      for (final entry in entries)
        if (entry.id != edited.id) entry,
      edited,
    ]..sort(_compareChronologically);

    final index = chronological.indexWhere((entry) => entry.id == edited.id);
    if (index < 0) {
      return false;
    }

    final previous = index > 0 ? chronological[index - 1] : null;
    final next = index < chronological.length - 1
        ? chronological[index + 1]
        : null;
    return (previous != null && edited.odometer < previous.odometer) ||
        (next != null && edited.odometer > next.odometer);
  }

  int _compareChronologically(OdometerEntry left, OdometerEntry right) {
    final eventCompare = left.eventDateTime.compareTo(right.eventDateTime);
    if (eventCompare != 0) {
      return eventCompare;
    }
    final createdCompare = left.createdAt.compareTo(right.createdAt);
    if (createdCompare != 0) {
      return createdCompare;
    }
    return left.id.compareTo(right.id);
  }
}
