# DriveTracker Architecture

## Foundation

DriveTracker is structured around small feature modules. UI screens depend on `DriveTrackerController`, which coordinates repositories and services. Repositories centralize SQLite access. Services own cross-table behavior and domain rules. Derived analytics live in repository/domain code and are passed to widgets as prepared models.

The app intentionally avoids a heavy architecture framework for Milestone 1. `provider` and `ChangeNotifier` are enough for predictable state updates across add/edit/archive/select/update flows.

## Database

Schema version: `4`

Tables:

- `vehicles`
  - Stable text `id` primary key.
  - Required identity fields: `name`, `make`, `model`, `fuel_type`, `distance_unit`.
  - Optional profile fields: `year`, `registration`, `photo_path`, `trim`, `engine`, `transmission`, `vin`, `colour`, `purchase_date`, `purchase_mileage`, `purchase_price`, `seller`, `notes`.
  - `is_archived` preserves records while removing vehicles from active selection.
  - `created_at` and `updated_at` track record lifecycle.
- `odometer_entries`
  - Stable text `id` primary key.
  - `vehicle_id` foreign key references `vehicles`.
  - `odometer` is a non-negative whole-unit reading.
  - `event_datetime` records when the vehicle event happened.
  - `created_at` and `updated_at` record when the app record was written.
  - `source_type` supports `MANUAL`, `REFUEL`, `EXPENSE`, `INCOME`, and `SERVICE`.
  - `source_record_id` links transactional records to their owned odometer entry.
- `app_settings`
  - Key/value settings for selected vehicle and theme preference.
- `record_categories`
  - Shared category table for `EXPENSE`, `INCOME`, and reserved `MAINTENANCE` categories.
  - Contains a stable text `id`, name, optional icon identifier, sort order, system/default flag, archived flag, and lifecycle timestamps.
  - Default expense and income categories are seeded by the V2 migration. Referenced categories should be archived rather than deleted.
- `refuels`
  - Stable text `id` primary key and `vehicle_id` foreign key.
  - `event_datetime`, `created_at`, and `updated_at` remain distinct.
  - Required historical vehicle event fields: odometer, fuel type, total cost, volume, unit price, full/partial tank state, and missed-previous-refuel flag.
  - Optional station and notes are stored as nullable text. Receipt attachments are linked through the shared `attachments` table.
- `expenses`
  - Standalone vehicle expenses with vehicle, category, event time, amount, optional odometer, merchant, payment method, notes, and lifecycle timestamps.
  - Fuel is not seeded as a normal expense category because refuels contribute directly to spending.
- `income_records`
  - Vehicle-related income with vehicle, category, event time, amount, optional odometer, source, notes, and lifecycle timestamps.
- `maintenance_items`
  - User-defined tracked work such as engine oil, filters, tyres, brake fluid, or a custom item.
  - Belongs to one vehicle and stores a name snapshot, optional category, optional mileage interval, optional time interval in days, warning thresholds, reminder flag, archived flag, and lifecycle timestamps.
  - Active item names are unique per vehicle case-insensitively. Archived items are hidden from active reminder lists but kept for historical integrity.
- `services`
  - One garage/workshop visit or maintenance event.
  - Stores vehicle, event date/time, optional odometer for imported baseline history, total cost in minor units, optional garage, notes, baseline flag, and lifecycle timestamps.
  - Normal service records require an odometer. Baseline records are zero-cost imported history and may omit odometer for time-only maintenance.
- `service_items`
  - Line items within a service record.
  - Each row belongs to one service and may reference a tracked maintenance item. It also stores an item-name snapshot so service history remains meaningful if the tracked item is later archived or renamed.
  - Optional allocated item cost and notes are metadata. Allocations do not add to spending totals.
- `documents`
  - Vehicle-specific document records with stable text `id`, `vehicle_id`, category, title, optional issue date, optional expiry date, optional reference number, provider, notes, derived-reminder identifier space, archive metadata, and lifecycle timestamps.
  - Dates are stored as local calendar date strings because document expiries are day-based records, not instants.
  - `is_archived` separates current documents from historical records. Renewals create a new row and archive the old row so previous dates/references/attachments remain intact.
- `attachments`
  - Shared polymorphic attachment metadata for `DOCUMENT`, `REFUEL`, `SERVICE`, `EXPENSE`, `INCOME`, and reserved future `VEHICLE` parents.
  - Stores stable text `id`, `parent_type`, `parent_id`, display `file_name`, portable relative `stored_path`, optional `mime_type`, optional `file_size`, and lifecycle timestamps.
  - SQLite cannot enforce a polymorphic parent foreign key, so services validate parent existence and coordinate cleanup.

Foreign keys are enabled on database open. Indexes support active vehicle filtering, per-vehicle odometer lookup, source-record odometer linkage, category type lookup, vehicle/date record lists, active maintenance lookup, service history, completion lookup, document expiry/category lists, attachment parent lookup, and month spend queries.

Milestone 6 advances schema version to 4 for documents and attachments. History filters and Insights remain derived from existing source tables and do not persist cached analytics snapshots.

## Migrations

`DatabaseMigrations` owns schema creation and upgrades. The app opens SQLite with `schemaVersion = 4`. Fresh V4 databases create V1 tables first, then V2 daily-record additions, V3 maintenance additions, and V4 document/attachment additions. Existing databases migrate through explicit V1 -> V2, V2 -> V3, and V3 -> V4 steps that preserve vehicles, archived vehicles, selected vehicle settings, odometer history, theme settings, refuels, expenses, income, categories, services, maintenance items, and service item history.

Future changes should add explicit migration steps instead of dropping and recreating user tables.

## Odometer Semantics

Odometer readings are stored as whole integer distance units, matching real-world odometers and avoiding decimal rounding problems. Each vehicle defines whether those units are miles or kilometers.

The current odometer is derived from the highest valid reading for that vehicle:

- A normal increase is accepted.
- A lower reading requires deliberate historical-entry confirmation.
- A lower historical entry does not rewind current odometer.
- A negative reading is rejected.
- An increase above the centralized large-jump threshold requires confirmation.

Event time, creation time, and update time are stored separately so refuel, service, and history features can handle historical records correctly.

Refuels and normal services create or update one linked odometer entry with their source type and source record ID. Expenses and income create a linked odometer entry only when the user supplies an odometer value. Editing a record updates that linked entry rather than inserting duplicates. Deleting a transactional record removes only the odometer row owned by that source record.

When a refuel, expense, income, or service record with attachments is deleted, its service calls the shared attachment cleanup path after the parent delete succeeds. Attachment metadata is deleted before managed files are removed.

Manual odometer entries remain independent. Unified activity queries show manual odometer entries, but linked refuel/expense/income/service odometer rows are represented by their owning records to avoid duplicate activity.

## Money And Fuel Precision

Persisted money uses integer minor units. The current default presentation is GBP, so `42.75` is stored as `4275` pence. Currency parsing and formatting are centralized in `core/utilities/money.dart` so future currency settings can replace the default without hunting through widgets.

Fuel volume is stored as integer millilitres. This keeps litre input decimal-friendly while avoiding display-formatted strings as data.

Fuel unit price is stored as integer micros of the major currency unit per litre. For GBP, `1.397 GBP/L` is stored as `1397000`. UK pence-per-litre input converts by the same canonical value, so `139.7 p/L` and `£1.397/L` are equivalent and cannot be mistaken for `£139.70/L`.

Service totals and optional service-item allocations also use integer minor units. The service total is the accounting value. Item allocations are an invoice breakdown only.

## Refuel Calculations

`FuelEntryCalculator` centralizes the relationship between total cost, fuel volume, and unit price. Any two positive values calculate the third. The latest two manually edited fields take precedence; the remaining field is recalculated, which prevents silently storing three conflicting values. Services validate that the stored triple remains internally consistent within minor-unit rounding tolerance.

## Fuel Economy Validity

Fuel economy is calculated only from trustworthy full-to-full intervals:

- A full tank starts an interval but its own litres are not counted.
- Partial fills after that start are accumulated.
- The ending full tank litres are included.
- Distance is ending odometer minus starting odometer.
- UK MPG for mile/litre vehicles is `miles / (litres * 0.219969)`.

Intervals are not produced when there is insufficient data, a missed-refuel flag within the candidate interval, non-progressing odometer readings, or unsupported units. A full-tank record that marks missed previous history invalidates the interval ending at that record; because the vehicle is known full at that point, it can become the next boundary, and only a later valid full tank can complete a new interval. Home shows an insufficient-data state instead of fabricated MPG.

## Maintenance And Service Records

Maintenance items define what the user wants to track for a specific vehicle. DriveTracker does not ship universal service intervals because intervals depend on the vehicle, manufacturer guidance, and usage. An item may have a mileage interval, a time interval, both, or neither. Reminder-disabled and interval-free items can still be recorded in service history.

A service record represents one real visit or maintenance event. It can contain multiple service items, each linked to a tracked maintenance item or stored as an untracked custom line. A linked service item is a completion event for that maintenance item. Completion history is derived from `services` joined to `service_items`; there is no mutable "last serviced" summary to drift out of sync.

Baseline last-completed information is represented as a zero-cost `services` row with `is_baseline = 1` and a linked service item. This preserves truthful history, supports mileage and date calculations, and does not create fake expense rows or service spend. Time-only baselines may omit odometer.

Archiving a maintenance item sets `is_archived = 1`. It removes the item from active management and reminder lists but does not delete service rows or service-item history. Existing service-item snapshots remain readable even if the item name changes or the item is archived.

## Reminder Engine

`MaintenanceReminderEngine` is the single source of maintenance due-state calculation. UI code receives reminder results and does not duplicate threshold logic.

For each maintenance item, the engine evaluates:

- latest completion date
- latest completion odometer
- next mileage due
- next date due
- miles remaining
- days remaining
- state

Mileage boundaries:

- `NORMAL`: more than the item mileage-warning threshold remaining, default 1000 units
- `UPCOMING`: less than or equal to the warning threshold
- `DUE_SOON`: less than or equal to 300 units
- `DUE`: exactly at due mileage
- `OVERDUE`: current odometer beyond due mileage

Date boundaries:

- `NORMAL`: more than the item date-warning threshold remaining, default 30 days
- `UPCOMING`: less than or equal to the warning threshold
- `DUE_SOON`: less than or equal to 7 days
- `DUE`: due today
- `OVERDUE`: past due

When both mileage and date intervals exist, both are evaluated and the more urgent state wins. No predicted future service dates are fabricated from mileage trends.

Document expiry reminders follow the same derived-reminder architecture rather than introducing persisted reminder rows. `DocumentService.remindersForVehicle` evaluates active, unarchived documents with recorded expiry dates against the controller's current time and maps them to the existing reminder state vocabulary:

- `UPCOMING`: expiry within 30 days
- `DUE_SOON`: expiry within 7 days
- `DUE`: expiry is today
- `OVERDUE`: recorded expiry date has passed

The Reminders screen renders document reminders beside maintenance reminders and opens the relevant document. Wording says "recorded expiry" or "expires in" and does not claim DriveTracker verified MOT, insurance, tax, ownership, or authenticity.

## Documents

`VehicleDocument` is the domain model for user-entered vehicle paperwork. Required fields are vehicle, category, title, and timestamps. Issue date, expiry date, reference number, provider, notes, and attachments are optional. Default UI categories include Insurance, MOT, V5C, Purchase receipt, Warranty, Breakdown cover, Tax, Finance / Lease, and Other, while the category text field keeps custom categories possible.

Document status is calculated dynamically:

- `NO_EXPIRY`: no expiry date recorded
- `VALID`: an expiry date exists and is more than 30 days away
- `EXPIRING_SOON`: expiry is today or within 30 days
- `EXPIRED`: expiry date is before the current local calendar day

Archiving hides a document from Current while keeping it in Archived / History and preserving attachments. Renewal archives the old document and creates a new active document from a user-edited draft. Old attachments stay with the historical document; they are not moved to the renewal. Permanent delete is behind confirmation and removes document attachment metadata and managed files.

## Attachments

Attachments are local-first and private. The database stores metadata only; file bytes are copied into app-controlled storage and are not stored as SQLite BLOBs. Persisted `stored_path` values are relative, for example `attachments/documents/<document-id>/<generated-id>.pdf`, so future backup/restore work can relocate files without rewriting absolute device paths.

Supported M6 file types are PDF, JPG/JPEG, and PNG. `AttachmentService.maxAttachmentBytes` is 20 MB per file. The service validates parent existence, source readability, extension/MIME, non-empty size, maximum size, and safe display filenames before accepting a file. Internal storage names use generated IDs, not user filenames, preventing path traversal and ordinary filename collisions. Original filenames remain display metadata only.

Adding an attachment copies the file first, verifies a managed path, then inserts metadata. If metadata insertion fails, the copied file is deleted where possible. Removing an attachment deletes metadata first and then performs best-effort managed-file cleanup. If a managed file is unexpectedly missing, the UI shows "File unavailable" and still allows metadata removal.

Android file picking and opening are implemented through a small `drivetracker/attachments` method channel. The picker uses Android's open-document UI for PDFs and images, copies content into an internal temporary file for Dart validation, and the Dart service then copies it into managed storage. Opening delegates to an installed Android viewer through a `FileProvider` content URI. No cloud picker, sync, OCR, PDF renderer, or document verification is included.

## Data Safety

Milestone 8 keeps schema version `4` and introduces backup, restore, and CSV export through `DataSafetyService`. Backup format version `1` stores a manifest, database table data, and managed attachment files using portable relative paths. CSV export is a separate spreadsheet-review path and is not treated as a backup format.

Restore is intentionally conservative. The app inspects a selected backup first, displays its manifest facts, requires explicit confirmation, creates a safety backup of the current local state, and then replaces local data. If restore fails, the service preserves the existing data where possible and reports a user-facing `DataSafetyException`. UI polish must not bypass confirmation, alter safety-backup creation, or change the backup manifest contract.

## Financial Aggregation

Vehicle spending is currently:

`refuel spending + standalone expenses + non-baseline service totals`

Income is not included in spending. Refuels do not generate standalone expense rows, and services do not generate standalone expense rows, so each transaction is counted once. Service-item allocated costs are not added on top of the service total.

Month spending uses `event_datetime` and the user's local calendar month, not `created_at`.

Six-month spending trends are fixed local-calendar month buckets ending with the current month. Empty months remain present with zero spend so Home can render a truthful trend without inventing values.

## History Filtering

`HistoryFilter` is the typed filter contract for the unified History screen and Insights drill-down. It supports:

- selected vehicle or all active vehicles
- all/fuel/service/expense/income/odometer record type
- all, week, month, year, or custom local-calendar date range
- expense/income category
- text search across stored user-facing text

`ActivityRepository.search` owns the filtering. It queries the source record tables directly, joins category and vehicle metadata where needed, and sorts the unified results by `event_datetime DESC, created_at DESC`. Linked odometer rows from refuels, expenses, income, and services are represented by their owning record, so History does not duplicate financial activity. Manual odometer rows remain visible and open a read-only detail dialog because they do not yet have a separate edit form.

History date filters and Insights ranges share `AnalyticsDateRange`. Ranges use local calendar boundaries and SQL receives UTC ISO strings for the end-exclusive stored comparison. Custom ranges validate `start <= end` and convert the inclusive end day to an end-exclusive boundary.

## Insights Architecture

`InsightsRepository` prepares one `VehicleInsights` model for a vehicle or all active vehicles and a resolved range. Widgets receive totals, availability reasons, chart buckets, breakdown rows, and trend points; they do not query SQLite or duplicate calculation rules.

The summary model exposes:

- fuel spend from `refuels.total_cost_minor`
- service spend from non-baseline `services.total_cost_minor`
- standalone expense spend from `expenses.amount_minor`
- total expenditure as fuel + service + standalone expense
- income from `income_records.amount_minor`
- net as income - total expenditure
- running spend and cost-per-distance when safely available
- weighted fuel price
- aggregate valid full-to-full fuel economy
- spending, income, fuel price, fuel economy, and odometer trend data
- source period/type/category metadata for drill-down to History

### Distance Algorithm

Distance is calculated only for a single selected vehicle. All Vehicles never combines odometers.

For one vehicle:

1. Read every odometer entry for the vehicle ordered by `event_datetime ASC, created_at ASC`.
2. Build a valid chronological sequence by keeping readings that are greater than or equal to the highest accepted reading so far. A later lower reading is treated as historical/inconsistent for distance purposes and ignored, while an older lower reading with an older event date remains valid.
3. Choose the start reading as the last valid reading at or before the range start. If there is no such boundary reading, use the first valid reading inside the range.
4. Choose the end reading as the last valid reading before the end-exclusive range boundary, or the latest valid reading for all-time ranges.
5. If fewer than two distinct valid readings are available, distance is unavailable. If the odometer delta is zero across two readings, zero distance is returned truthfully, and per-distance cost metrics remain unavailable to avoid divide-by-zero.

### Fuel Economy Algorithm

Fuel economy reuses `FuelEconomyCalculator.validIntervals`:

- a full tank starts a boundary
- partial fills between boundaries accumulate
- the ending full tank litres are included
- missed-refuel flags invalidate the affected interval and allow a new sequence to resume once the tank state is trustworthy
- non-progressing odometers and unsupported units produce no interval

For an Insights range, valid intervals whose ending full refuel event is inside the range are aggregated. MPG is calculated from total valid distance divided by total valid litres converted to imperial gallons. Individual MPG values are not averaged.

### Weighted Fuel Price

Average fuel price is volume-weighted for refuels in the selected range:

`total fuel cost / total fuel volume`

The repository calculates this from `total_cost_minor` and `volume_millilitres`, returning micros per litre so existing fuel-price formatters can display pence per litre.

### Running Versus Total Cost

Total expenditure includes all refuel spend, non-baseline service spend, and standalone expense spend.

Running/usage-oriented spend includes:

- all refuel spend
- all non-baseline service spend
- seeded expense categories for parking, tolls, repairs, parts, cleaning, and other

Insurance, tax, MOT, fines, subscriptions, and custom expense categories are included in total expenditure but not assumed to be running cost because the current schema cannot reliably infer their usage relationship from a custom display name.

### Chart Bucketing

`AnalyticsDateRange` creates local-calendar buckets:

- Week: daily buckets
- Month: weekly buckets
- Year: monthly buckets
- All: monthly buckets for shorter spans, yearly buckets for longer spans
- Custom: daily, weekly, monthly, or yearly buckets according to duration

Bounded ranges retain empty buckets so charts show truthful time context. All-time ranges use the real earliest and latest financial events; if there are no source events, no chart points are fabricated.

## All Vehicles Insights

All Vehicles safely aggregates expenditure, income, net, spending buckets, category breakdown, and weighted fuel price across active vehicles. It deliberately marks distance, fuel economy, odometer trend, running cost per distance, and total expenditure per distance unavailable because odometers and MPG intervals are vehicle-specific and cannot be combined without misleading the user.

## Insights Presentation

The Insights screen is a real dashboard with vehicle scope, week/month/year/all/custom ranges, summary metrics, an interactive spending chart, spending breakdown, fuel insight section, mileage section, and optional income/net section. Tapping spending buckets, category breakdown selections, or fuel drill-down opens History with a concrete `HistoryFilter` for the matching period/type/category instead of using global mutable state.

The screen avoids large subtree animations and whole-screen transitions. It uses ordinary Material ink interactions, finite-width controls, horizontal chart scrolling for dense buckets, semantic labels for tappable chart data, and unavailable states when the data is insufficient.

## Home Dashboard

`HomeRepository` composes the selected vehicle dashboard from existing repositories instead of storing a duplicated dashboard snapshot. The dashboard contract includes the vehicle identity, current odometer, recent odometer entries, current-month spending, latest refuel price, latest valid full-to-full MPG interval, recent activity, maintenance attention, and six-month spending trend.

Home maintenance attention only surfaces active reminder-enabled items that need setup or are upcoming, due soon, due, or overdue. Normal and archived items remain available in maintenance screens but do not crowd the Home dashboard.

## Presentation System

Milestone 9 does not add a migration, persistence table, or business rule. It consolidates presentation around `DTTheme`, `DTSpacing`, `DTRadii`, `DTAccents`, and reusable widgets such as `DTCategoryIcon`, `DTStatusBadge`, `DTListCard`, `DTMetricCard`, `DTActivityRow`, and `DTFormSection`.

The visual system uses restrained semantic accents for fuel, service, expense, income, odometer, maintenance, documents, and storage. Those accents are presentation hints only; state and meaning are still conveyed through labels, icons, and domain values so the UI does not rely on color alone. Layouts prefer finite constraints, `Wrap`, `Flexible`, and horizontal scroll only where controls can legitimately exceed a narrow phone width.

Motion is deliberately local and deterministic: Material ink feedback, the central add-button press scale, chart selection, and ordinary route/sheet transitions. M9 avoids large dashboard entrance animations, continuous effects, network imagery, and fabricated vehicle data.

## Tools And Fuel Calculator

Milestone 7 keeps schema version `4`; it adds no migration and no calculator persistence table. Calculator state is ephemeral UI state. Results never create refuel, expense, income, service, odometer, document, attachment, or history rows.

`lib/features/calculator/domain/fuel_calculator.dart` owns the calculation model:

- `FuelUnitConversions` converts miles/kilometres, litres/Imperial gallons/US gallons, and economy values.
- `TripCostInput` and `TripCostResult` estimate fuel required, fuel cost, and cost per distance.
- `CostSharingInput` and `CostSharingResult` split a known fuel cost or a calculated trip cost.
- `FuelRequiredInput` and `FuelRequiredResult` expose litres plus Imperial and US gallon equivalents.
- `FuelPriceComparisonInput` and `FuelPriceComparisonResult` compare station prices and optional additional round-trip travel cost.
- `VehicleFuelDefaults` packages the selected vehicle's safe calculator defaults from the existing dashboard data.

Fuel calculator constants are centralized: `1 mile = 1.609344 km`, `1 Imperial gallon = 4.54609 L`, and `1 US gallon = 3.785411784 L`. UK MPG, US MPG, L/100 km, and km/L conversion goes through litres-per-100-kilometres so reciprocal units cannot be treated as linear values.

Vehicle defaults deliberately reuse existing trusted data. The selected vehicle can provide its latest valid full-to-full UK MPG interval from `FuelEconomyCalculator.validIntervals` and latest recorded refuel price from `HomeRepository`/`VehicleDashboard`. Partial fills, missed-refuel sequences, non-progressing odometers, unsupported distance units, and insufficient history do not fabricate an economy default. Selecting another vehicle refreshes defaults for that vehicle only; manual values remain available.

The Fuel Calculator screen is reached from More -> Fuel Calculator. It presents Trip Cost, Cost Sharing, Fuel Required, and Price Comparison as modes of one tool surface, uses numeric keyboards and unit suffixes, labels results as estimates, distinguishes "From vehicle" from "Manual", and uses finite-width responsive field/result layouts for narrow Android screens and wider test viewports.

## Dependency Decisions

- `sqflite` is the mature mobile SQLite package used for Android persistence.
- `sqflite_common_ffi` is used in tests and keeps the database layer compatible with future Windows work.
- `provider` keeps app state lightweight and understandable for this milestone.
- No routing package was added because the current navigation is small and imperative routes keep the dependency surface lower.
- No Flutter picker/path/open-file packages were added for Milestone 6. Android-first file selection, managed-root discovery, and external opening use the existing Flutter method-channel capability plus a small Android implementation, keeping `pubspec.yaml` and `pubspec.lock` unchanged.
- No dependencies were added for Milestone 7. Fuel calculator formulas and UI use Dart, Flutter Material, and existing DriveTracker utilities.
- No dependencies were added for Milestone 9. Polish work uses Flutter Material, existing widgets, and DriveTracker's shared design tokens.
- No analytics, telemetry, sync, account, or cloud packages are included.
