# DriveTracker

DriveTracker is a local-first Flutter application for managing vehicles, mileage, fuel, expenses, and vehicle-related income without accounts, telemetry, cloud APIs, or fabricated dashboard data.

## Current Milestone

Implemented through Milestone 7:

- Material 3 app shell with Home, Insights, central add action, Reminders, and More.
- First-run flow from welcome screen to adding the first vehicle.
- SQLite schema version 4 with controlled migrations from V1, V2, and V3.
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
- Vehicle Documents for selected-vehicle records such as Insurance, MOT, V5C, purchase receipts, warranties, breakdown cover, tax, finance/lease paperwork, and custom document categories.
- Document lifecycle support with active/current documents, archived history, renewal that preserves old records, and deliberate permanent delete.
- Local file attachments for documents, refuels, services, expenses, and income records, storing metadata in SQLite while copying PDFs/JPG/JPEG/PNG files into DriveTracker-managed app storage.
- Document expiry reminders derived from recorded expiry dates and shown in the Reminders screen without claiming external verification.
- Tools entry under More with a polished Fuel Calculator for Trip Cost, Cost Sharing, Fuel Required, and Fuel Price Comparison.
- Pure calculator domain logic for miles/kilometres, litres/Imperial gallons/US gallons, UK MPG, US MPG, L/100 km, and km/L conversion.
- Selected-vehicle calculator defaults that can use the current vehicle's latest trustworthy full-to-full fuel economy and latest recorded fuel price, while keeping manual input available and clearly labelled.
- Ephemeral fuel estimates that do not create refuels, expenses, services, odometer readings, calculator history, or any other persisted vehicle record.
- Settings foundation for system, light, and dark theme preferences.
- Unit and widget tests for vehicle, odometer, persistence, daily records, service records, maintenance calculations, Home dashboard aggregation, spending trends, History filters, Insights calculations, drill-down, migrations, document lifecycle, attachments, calculator formulas/defaults/UI, layout states, and important UI flows.

Deferred to later milestones:

- Notifications, exports, backup/restore, sync, accounts, OCR, and external vehicle integrations.

## Technology

- Flutter 3.47.2 / Dart 3.13.2
- Material 3
- SQLite via `sqflite`
- `sqflite_common_ffi` for repository tests and future desktop compatibility
- `provider` for lightweight app state
- `path` for database and managed attachment path handling

## Architecture

The project uses a feature-oriented structure:

- `lib/app`: app bootstrap, controller, navigation shell, and theme.
- `lib/core`: database, migrations, formatting, IDs, and shared utilities.
- `lib/features/vehicles`: vehicle model, validation, repository, service, and UI.
- `lib/features/odometer`: odometer model, policy, repository, service, and update UI.
- `lib/features/daily_records`: refuel, expense, income, category, calculation, activity, History filtering, repository, service, form, and History code.
- `lib/features/maintenance`: maintenance item, service record, service item, reminder engine, repositories, services, forms, detail screen, management screen, and Reminders integration.
- `lib/features/documents`: vehicle document model, repository, service, expiry reminders, Documents list, form, and detail screens.
- `lib/features/attachments`: polymorphic attachment metadata, managed-file storage, Android picker/open bridge, service, and reusable attachment panel.
- `lib/features/calculator`: pure fuel calculator domain logic and the More-accessible calculator UI.
- `lib/features/home`: dashboard data contract and Home UI.
- `lib/features/insights`: derived analytics repository, range-aware insight models, and the Insights dashboard.
- `lib/features/reminders`, `lib/features/more`, `lib/features/settings`: milestone screens and settings foundation.
- `lib/core/calculations`: reusable local-calendar date-range and bucket rules for analytics and History filtering.
- `lib/shared/widgets`: reusable DriveTracker UI components used by current screens.

Presentation widgets do not issue raw SQL. Business rules live in validators and services so they can be tested outside widgets.

## History And Insights

History queries are repository-owned and use `event_datetime`, not `created_at`. Filters support selected or all active vehicles, record type, all/week/month/year/custom date ranges, expense/income category, and text search across useful stored fields such as notes, merchant/source, garage, station, category, service item text, odometer text, and vehicle identity.

Insights are derived, not persisted. Milestone 6 moves the source schema to V4 for documents and attachments, but analytics mathematics still uses the same financial source tables. Spending is:

`refuels + non-baseline service totals + standalone expenses`

Income stays separate, and net is `income - expenditure`. Service item allocations are invoice breakdown metadata and are not added on top of service totals.

Distance is available only for one selected vehicle. Readings are sorted by event time, lower readings after a higher chronological reading are ignored, and the range distance uses the last valid reading at or before the range start when available, otherwise the first valid in-range reading, minus the last valid reading before the range end. Fewer than two valid readings is unavailable; two equal readings produce a genuine zero distance, which keeps cost-per-distance unavailable instead of dividing by zero.

Fuel economy uses the existing full-to-full interval rules. Insights include only valid intervals whose ending full refuel is inside the selected range, then aggregate by total valid distance divided by total valid litres converted to imperial gallons. MPG values are not averaged naively.

Average fuel price is volume-weighted from real refuels in the range: total fuel cost divided by total litres. Running cost includes fuel, service/maintenance, and seeded usage expense category IDs for parking, tolls, repairs, parts, cleaning, and other. Broader ownership expenses such as insurance, tax, MOT, fines, subscriptions, and custom categories remain in total expenditure but are not assumed to be usage-oriented.

Charts use local-calendar buckets: week uses days, month uses weekly buckets, year uses months, and all/custom ranges choose month or year buckets as the span grows. Empty buckets are retained for bounded ranges so the time context stays truthful. Tapping spending buckets, breakdown categories, and fuel sections opens History with matching filters.

All Vehicles aggregates spending, income, net, category breakdown, and weighted fuel price. It intentionally marks odometer distance, MPG, and cost-per-distance unavailable because unrelated vehicle odometers and MPG intervals are not mathematically safe to combine.

See `docs/architecture.md` for the schema and design notes.

## Documents And Attachments

Documents are vehicle-specific user records. DriveTracker stores titles, categories, optional provider/reference/notes, issue dates, expiry dates, archive state, and lifecycle timestamps. Status is derived from the recorded expiry date: no expiry, recorded, expiring soon within 30 days, or expired after the date has passed. This is only a local record of what the user entered; DriveTracker does not verify MOT, tax, insurance, ownership, document authenticity, or legal validity.

Attachments are optional. SQLite stores attachment metadata and a portable relative path. Actual file bytes are copied into DriveTracker-managed application storage under `attachments/<parent-type>/<parent-id>/<generated-id>.<extension>`, not stored as BLOBs and not permanently linked to external picker locations. Supported files are PDF, JPG/JPEG, and PNG up to 20 MB each. Deletion removes database metadata before best-effort managed-file cleanup so filesystem failures do not corrupt record metadata.

## Tools And Fuel Calculator

Milestone 7 adds a Fuel Calculator from More without changing the database schema. The screen contains four modes in one calculator system:

- Trip Cost estimates fuel required, fuel cost, and cost per distance unit.
- Cost Sharing splits a known fuel cost or an estimated trip fuel cost between people.
- Fuel Required converts a distance and economy into litres, Imperial gallons, and US gallons.
- Price Comparison compares two station prices per litre and can subtract the estimated fuel cost of an additional round-trip distance.

Calculator formulas live in `lib/features/calculator/domain` and are not embedded in widgets. Unit conversion uses precise constants for miles/kilometres, Imperial gallons, and US gallons. Economy conversion treats L/100 km and km/L as reciprocal units rather than linear labels.

The calculator can copy defaults from the selected vehicle when available: the latest trustworthy full-to-full UK MPG interval and the latest recorded fuel price. It never combines vehicles, never uses All Vehicles as a trip-economy source, and never fabricates economy from partial or missed refuel history. If defaults are missing, the same tools remain usable with manual values.

Calculator results are estimates. They are labelled as based on recorded or manual values and are not saved as transactions, history, refuels, expenses, services, or odometer readings.

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

DriveTracker is local-first. It stores vehicle, odometer, refuel, expense, income, category, service, maintenance, document, and attachment metadata in a local SQLite database on the device. Managed attachment files stay in app-controlled local storage. Calculator inputs and results are not persisted. It does not require login, internet access, analytics SDKs, advertising SDKs, or cloud sync.

## Roadmap Summary

Next milestones can add notifications, exports, backup/restore, and optional integrations. These should build on the existing repository/service boundaries, schema migration path, and portable relative attachment paths rather than replacing user data.
