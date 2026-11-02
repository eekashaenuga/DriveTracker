import 'package:drivetracker/features/vehicles/domain/vehicle.dart';
import 'package:drivetracker/features/vehicles/domain/vehicle_draft.dart';
import 'package:drivetracker/core/calculations/analytics_date_range.dart';
import 'package:drivetracker/features/reports/domain/report_request.dart';

import 'test_services.dart';

final reportNow = DateTime(2026, 10, 24, 12);
ReportRequest reportRequest(
  String id, {
  Set<ReportSection>? sections,
  ReportFormat format = ReportFormat.xlsx,
  AnalyticsDateRange? range,
  bool sensitive = false,
}) => ReportRequest(
  vehicleId: id,
  range: range ?? AnalyticsDateRange.month,
  sections: sections ?? ReportSection.values.toSet(),
  format: format,
  includeSensitive: sensitive,
);
Future<(TestServices, String)> reportFixture({
  int expenses = 3,
  bool complete = false,
}) async {
  final s = createTestServices();
  final v = await s.vehicleService.addVehicle(
    VehicleDraft(
      name: 'My Fiesta',
      make: 'Ford',
      model: 'Fiesta',
      year: 2018,
      registration: 'AB12 CDE',
      fuelType: FuelType.petrol,
      distanceUnit: DistanceUnit.miles,
      currentOdometer: 1000,
      purchaseDate: DateTime(2026, 9, 1),
      purchasePrice: 2500,
      vin: 'PRIVATE-VIN',
      seller: 'PRIVATE-SELLER',
      notes: 'PRIVATE-VEHICLE-NOTES',
    ),
  );
  final db = await s.database.database;
  final at = DateTime(2026, 10, 2, 12).toUtc().toIso8601String();
  Map<String, Object?> common(String id) => {
    'id': id,
    'vehicle_id': v.id,
    'event_datetime': at,
    'created_at': at,
    'updated_at': at,
  };
  await db.transaction((t) async {
    for (var i = 0; i < expenses; i++) {
      await t.insert('expenses', {
        ...common('e$i'),
        'category_id': 'cat_expense_parking',
        'amount_minor': 100,
        'merchant': '=SUM(A1:A2)',
        'notes': i == 0 ? '£ café – Ελληνικά Привет' : 'notes $i',
      });
    }
    final outside = DateTime(2026, 9, 2, 12).toUtc().toIso8601String();
    await t.insert('expenses', {
      ...common('outside'),
      'event_datetime': outside,
      'category_id': 'cat_expense_parking',
      'amount_minor': 250,
    });
    for (final (id, type) in [('driving', 'delivery'), ('legacy', 'simple')]) {
      await t.insert('income_records', {
        ...common(id),
        'category_id': 'cat_income_delivery',
        'amount_minor': 1000,
        'activity_type': type,
        if (type == 'delivery') ...{
          'base_amount_minor': 700,
          'tips_minor': 100,
          'travel_compensation_minor': 100,
          'other_income_minor': 100,
          'activity_distance_mm': 16093440,
          'duration_minutes': 60,
          'delivery_count': 2,
          'direct_costs_complete': complete ? 1 : 0,
        },
      });
    }
    await t.insert('income_activity_expenses', {
      'income_id': 'driving',
      'expense_id': 'outside',
      'created_at': at,
    });
    await t.insert('services', {
      ...common('service'),
      'total_cost_minor': 500,
      'garage': 'Local garage',
      'is_baseline': 0,
    });
    await t.insert('services', {
      ...common('baseline'),
      'total_cost_minor': 0,
      'is_baseline': 1,
    });
    for (var i = 0; i < 2; i++) {
      await t.insert('service_items', {
        'id': 'si$i',
        'service_id': 'service',
        'item_name': 'Oil and filter $i',
        'allocated_cost_minor': i == 0 ? 0 : null,
        'created_at': at,
        'updated_at': at,
      });
    }
    for (var i = 0; i < 5; i++) {
      await t.insert('refuels', {
        ...common('fuel$i'),
        'event_datetime': DateTime(
          2026,
          9,
          28 + i * 4,
          12,
        ).toUtc().toIso8601String(),
        'odometer': 1000 + i * 200,
        'fuel_type': 'PETROL',
        'total_cost_minor': 6000,
        'volume_millilitres': 40001,
        'unit_price_micros_per_litre': 1500123,
        'is_full_tank': 1,
        'missed_previous_refuel': i == 2 ? 1 : 0,
        'station': 'Station $i',
      });
    }
    await t.update(
      'record_categories',
      {'is_archived': 1},
      where: 'id = ?',
      whereArgs: ['cat_expense_parking'],
    );
    await t.insert('documents', {
      'id': 'tax',
      'vehicle_id': v.id,
      'category': 'Vehicle tax',
      'title': 'Vehicle tax record',
      'issue_date': '2026-01-01',
      'expiry_date': '2027-01-01',
      'reference_number': 'PRIVATE-POLICY',
      'notes': 'PRIVATE-DOC-NOTES',
      'is_archived': 0,
      'created_at': at,
      'updated_at': at,
    });
  });
  return (s, v.id);
}
