# DriveTracker Architecture

## Foundation

DriveTracker is structured around small feature modules. UI screens depend on `DriveTrackerController`, which coordinates repositories and services. Repositories centralize SQLite access. Services own cross-table behavior and domain rules. Derived analytics live in repository/domain code and are passed to widgets as prepared models.

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

Milestone 5 keeps schema version 3. History filters and Insights are derived from existing source tables and do not persist cached analytics snapshots.

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

## Dependency Decisions

- `sqflite` is the mature mobile SQLite package used for Android persistence.
- `sqflite_common_ffi` is used in tests and keeps the database layer compatible with future Windows work.
- `provider` keeps app state lightweight and understandable for this milestone.
- No routing package was added because the current navigation is small and imperative routes keep the dependency surface lower.
- No analytics, telemetry, sync, account, or cloud packages are included.
