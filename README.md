# DriveTracker

DriveTracker is a local-first Flutter application for managing vehicles, mileage, fuel, expenses, and vehicle-related income without accounts, telemetry, cloud APIs, or fabricated dashboard data.

## Current Milestone

Implemented through Milestone 5:

- Material 3 app shell with Home, Insights, central add action, Reminders, and More.
- First-run flow from welcome screen to adding the first vehicle.
- SQLite schema version 3 with controlled migrations from V1 and V2.
- Vehicle creation, editing, listing, switching, and archiving.
- Multiple active vehicles with persisted selected vehicle.
- Odometer entries with manual readings and historical lower-reading confirmation.
- Refuelling records with full/partial tank state, missed-refuel marking, and linked odometer entries.
- Smart fuel entry calculation where any two of total cost, volume, and unit price calculate the third.
- UK-friendly fuel price entry using pence per litre or pounds per litre with one canonical stored value.
- Trustworthy full-to-full UK MPG calculation when enough valid fuel history exists.
- Standalone vehicle expenses with seeded and custom categories.
- Vehicle-related income with seeded and custom categories.
- Service records with one garage visit containing one or more tracked or untracked service items.
- User-defined maintenance items with optional mileage intervals, date intervals, warning thresholds, and archiving.
- A calculated reminder engine for normal, upcoming, due-soon, due, and overdue maintenance states.
- Zero-cost baseline maintenance history for establishing last-completed mileage/date without creating fake spend.
- Functional Reminders screen for the selected vehicle, including direct "Record service" flows.
- Unified History for fuel, expense, income, service, and manual odometer records, with vehicle, record type, date-range, category, and text-search filters.
- Home dashboard backed by stored vehicle, odometer, refuel, expense, service, and maintenance reminder data, including selected-vehicle switching, odometer updates, monthly spend, latest fuel price, latest full-to-full MPG, maintenance attention, recent activity, History access, and a six-month spending trend.
- Insights dashboard backed only by stored records, including expenditure/income/net summaries, distance availability, weighted fuel price, aggregate full-to-full MPG, spending buckets, category breakdowns, fuel and odometer trend data, and drill-down into filtered History.
- Settings foundation for system, light, and dark theme preferences.
- Unit and widget tests for vehicle, odometer, persistence, daily records, service records, maintenance calculations, Home dashboard aggregation, spending trends, History filters, Insights calculations, drill-down, migrations, layout states, and important UI flows.

Deferred to later milestones:

- Documents, notifications, exports, backup/restore, sync, accounts, OCR, and external vehicle integrations.

## Technology

- Flutter 3.47.2 / Dart 3.13.2
- Material 3
- SQLite via `sqflite`
- `sqflite_common_ffi` for repository tests and future desktop compatibility
- `provider` for lightweight app state
- `path` for database path handling

## Architecture

The project uses a feature-oriented structure:

- `lib/app`: app bootstrap, controller, navigation shell, and theme.
- `lib/core`: database, migrations, formatting, IDs, and shared utilities.
- `lib/features/vehicles`: vehicle model, validation, repository, service, and UI.
- `lib/features/odometer`: odometer model, policy, repository, service, and update UI.
- `lib/features/daily_records`: refuel, expense, income, category, calculation, activity, History filtering, repository, service, form, and History code.
- `lib/features/maintenance`: maintenance item, service record, service item, reminder engine, repositories, services, forms, detail screen, management screen, and Reminders integration.
- `lib/features/home`: dashboard data contract and Home UI.
- `lib/features/insights`: derived analytics repository, range-aware insight models, and the Insights dashboard.
- `lib/features/reminders`, `lib/features/more`, `lib/features/settings`: milestone screens and settings foundation.
- `lib/core/calculations`: reusable local-calendar date-range and bucket rules for analytics and History filtering.
- `lib/shared/widgets`: reusable DriveTracker UI components used by current screens.

Presentation widgets do not issue raw SQL. Business rules live in validators and services so they can be tested outside widgets.

## History And Insights

History queries are repository-owned and use `event_datetime`, not `created_at`. Filters support selected or all active vehicles, record type, all/week/month/year/custom date ranges, expense/income category, and text search across useful stored fields such as notes, merchant/source, garage, station, category, service item text, odometer text, and vehicle identity.

Insights are derived, not persisted. Schema version remains 3 because Milestone 5 adds no new source data. Spending is:

`refuels + non-baseline service totals + standalone expenses`

Income stays separate, and net is `income - expenditure`. Service item allocations are invoice breakdown metadata and are not added on top of service totals.

Distance is available only for one selected vehicle. Readings are sorted by event time, lower readings after a higher chronological reading are ignored, and the range distance uses the last valid reading at or before the range start when available, otherwise the first valid in-range reading, minus the last valid reading before the range end. Fewer than two valid readings is unavailable; two equal readings produce a genuine zero distance, which keeps cost-per-distance unavailable instead of dividing by zero.

Fuel economy uses the existing full-to-full interval rules. Insights include only valid intervals whose ending full refuel is inside the selected range, then aggregate by total valid distance divided by total valid litres converted to imperial gallons. MPG values are not averaged naively.

Average fuel price is volume-weighted from real refuels in the range: total fuel cost divided by total litres. Running cost includes fuel, service/maintenance, and seeded usage expense category IDs for parking, tolls, repairs, parts, cleaning, and other. Broader ownership expenses such as insurance, tax, MOT, fines, subscriptions, and custom categories remain in total expenditure but are not assumed to be usage-oriented.

Charts use local-calendar buckets: week uses days, month uses weekly buckets, year uses months, and all/custom ranges choose month or year buckets as the span grows. Empty buckets are retained for bounded ranges so the time context stays truthful. Tapping spending buckets, breakdown categories, and fuel sections opens History with matching filters.

All Vehicles aggregates spending, income, net, category breakdown, and weighted fuel price. It intentionally marks odometer distance, MPG, and cost-per-distance unavailable because unrelated vehicle odometers and MPG intervals are not mathematically safe to combine.

See `docs/architecture.md` for the schema and design notes.

## Run

```bash
flutter pub get
flutter run
```

The app is Android-first for this milestone, while keeping the database layer compatible with future Windows support.

## Test And Validate

```bash
dart format .
flutter analyze
flutter test
flutter build apk --debug
```

## Privacy

DriveTracker is local-first. It stores vehicle, odometer, refuel, expense, income, category, service, and maintenance data in a local SQLite database on the device. It does not require login, internet access, analytics SDKs, advertising SDKs, or cloud sync.

## Roadmap Summary

Next milestones can add documents, notifications, exports, backup/restore, and optional integrations. These should build on the existing repository/service boundaries and schema migration path rather than replacing user data.
