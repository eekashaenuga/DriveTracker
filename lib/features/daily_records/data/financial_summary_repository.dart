import '../domain/monthly_spending.dart';
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

    return spendingForVehicleBetween(
      vehicleId,
      startInclusive: start,
      endExclusive: end,
    );
  }

  Future<int> spendingForVehicleBetween(
    String vehicleId, {
    required DateTime startInclusive,
    required DateTime endExclusive,
  }) async {
    final fuelSpend = await refuelRepository.spendingForVehicleBetween(
      vehicleId,
      startInclusive: startInclusive,
      endExclusive: endExclusive,
    );
    final expenseSpend = await expenseRepository.spendingForVehicleBetween(
      vehicleId,
      startInclusive: startInclusive,
      endExclusive: endExclusive,
    );
    final serviceSpend = await serviceRecordRepository
        .spendingForVehicleBetween(
          vehicleId,
          startInclusive: startInclusive,
          endExclusive: endExclusive,
        );
    return fuelSpend + expenseSpend + serviceSpend;
  }

  Future<List<MonthlySpending>> spendingTrendForVehicle(
    String vehicleId, {
    DateTime? now,
    int monthCount = 6,
  }) async {
    if (monthCount <= 0) {
      return const [];
    }

    final localNow = (now ?? DateTime.now()).toLocal();
    final currentMonth = DateTime(localNow.year, localNow.month);
    final trend = <MonthlySpending>[];
    for (var index = monthCount - 1; index >= 0; index -= 1) {
      final month = DateTime(currentMonth.year, currentMonth.month - index);
      final nextMonth = DateTime(month.year, month.month + 1);
      trend.add(
        MonthlySpending(
          month: month,
          amountMinor: await spendingForVehicleBetween(
            vehicleId,
            startInclusive: month,
            endExclusive: nextMonth,
          ),
        ),
      );
    }
    return trend;
  }

  Future<Refuel?> latestRefuelForVehicle(String vehicleId) {
    return refuelRepository.latestForVehicle(vehicleId);
  }
}
