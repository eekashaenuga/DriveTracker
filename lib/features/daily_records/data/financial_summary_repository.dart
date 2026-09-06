import '../domain/refuel.dart';
import 'expense_repository.dart';
import 'refuel_repository.dart';
import '../../maintenance/data/service_record_repository.dart';

class FinancialSummaryRepository {
  FinancialSummaryRepository({
    required this.refuelRepository,
    required this.expenseRepository,
    required this.serviceRecordRepository,
  });

  final RefuelRepository refuelRepository;
  final ExpenseRepository expenseRepository;
  final ServiceRecordRepository serviceRecordRepository;

  Future<int> monthSpendForVehicle(String vehicleId, {DateTime? now}) async {
    final localNow = (now ?? DateTime.now()).toLocal();
    final start = DateTime(localNow.year, localNow.month);
    final end = DateTime(localNow.year, localNow.month + 1);

    final fuelSpend = await refuelRepository.spendingForVehicleBetween(
      vehicleId,
      startInclusive: start,
      endExclusive: end,
    );
    final expenseSpend = await expenseRepository.spendingForVehicleBetween(
      vehicleId,
      startInclusive: start,
      endExclusive: end,
    );
    final serviceSpend = await serviceRecordRepository
        .spendingForVehicleBetween(
          vehicleId,
          startInclusive: start,
          endExclusive: end,
        );
    return fuelSpend + expenseSpend + serviceSpend;
  }

  Future<Refuel?> latestRefuelForVehicle(String vehicleId) {
    return refuelRepository.latestForVehicle(vehicleId);
  }
}
