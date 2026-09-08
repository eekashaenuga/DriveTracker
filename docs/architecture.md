# DriveTracker Architecture

## Foundation

DriveTracker is structured around small feature modules. UI screens depend on `DriveTrackerController`, which coordinates repositories and services. Repositories centralize SQLite access. Services own cross-table behavior and domain rules.

The app intentionally avoids a heavy architecture framework for Milestone 1. `provider` and `ChangeNotifier` are enough for predictable state updates across add/edit/archive/select/update flows.

## Database

Schema version: `3`

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
  - Optional station and notes are stored as nullable text. Receipt attachments and driver fields are left for later milestones.
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

Foreign keys are enabled on database open. Indexes support active vehicle filtering, per-vehicle odometer lookup, source-record odometer linkage, category type lookup, vehicle/date record lists, active maintenance lookup, service history, completion lookup, and month spend queries.

## Migrations

`DatabaseMigrations` owns schema creation and upgrades. The app opens SQLite with `schemaVersion = 3`. Fresh V3 databases create V1 tables first, then V2 daily-record additions, then V3 maintenance additions. Existing databases migrate through explicit V1 -> V2 and V2 -> V3 steps that preserve vehicles, archived vehicles, selected vehicle settings, odometer history, theme settings, refuels, expenses, income, and categories.

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

## Financial Aggregation

Vehicle spending is currently:

`refuel spending + standalone expenses + non-baseline service totals`

Income is not included in spending. Refuels do not generate standalone expense rows, and services do not generate standalone expense rows, so each transaction is counted once. Service-item allocated costs are not added on top of the service total.

Month spending uses `event_datetime` and the user's local calendar month, not `created_at`.

Six-month spending trends are fixed local-calendar month buckets ending with the current month. Empty months remain present with zero spend so Home can render a truthful trend without inventing values.

## Home Dashboard

`HomeRepository` composes the selected vehicle dashboard from existing repositories instead of storing a duplicated dashboard snapshot. The dashboard contract includes the vehicle identity, current odometer, recent odometer entries, current-month spending, latest refuel price, latest valid full-to-full MPG interval, recent activity, maintenance attention, and six-month spending trend.

Home maintenance attention only surfaces active reminder-enabled items that need setup or are upcoming, due soon, due, or overdue. Normal and archived items remain available in maintenance screens but do not crowd the Home dashboard.

## Dependency Decisions

- `sqflite` is the mature mobile SQLite package used for Android persistence.
- `sqflite_common_ffi` is used in tests and keeps the database layer compatible with future Windows work.
- `provider` keeps app state lightweight and understandable for this milestone.
- No routing package was added because the current navigation is small and imperative routes keep the dependency surface lower.
- No analytics, telemetry, sync, account, or cloud packages are included.
