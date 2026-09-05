# DriveTracker Architecture

## Foundation

DriveTracker is structured around small feature modules. UI screens depend on `DriveTrackerController`, which coordinates repositories and services. Repositories centralize SQLite access. Services own cross-table behavior and domain rules.

The app intentionally avoids a heavy architecture framework for Milestone 1. `provider` and `ChangeNotifier` are enough for predictable state updates across add/edit/archive/select/update flows.

## Database

Schema version: `2`

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
  - `source_type` supports `MANUAL`, `REFUEL`, `EXPENSE`, and `INCOME`; `SERVICE` remains reserved for a later milestone.
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

Foreign keys are enabled on database open. Indexes support active vehicle filtering, per-vehicle odometer lookup, source-record odometer linkage, category type lookup, vehicle/date record lists, and month spend queries.

## Migrations

`DatabaseMigrations` owns schema creation and upgrades. The app opens SQLite with `schemaVersion = 2`. Fresh V2 databases create V1 tables first and then V2 additions. Existing V1 databases migrate through an explicit V1 -> V2 step that preserves vehicles, archived vehicles, selected vehicle settings, odometer history, and theme settings.

Future changes should add explicit migration steps instead of dropping and recreating user tables.

## Odometer Semantics

Odometer readings are stored as whole integer distance units, matching real-world odometers and avoiding decimal rounding problems. Each vehicle defines whether those units are miles or kilometers.

The current odometer is derived from the highest valid reading for that vehicle:

- A normal increase is accepted.
- A lower reading requires deliberate historical-entry confirmation.
- A lower historical entry does not rewind current odometer.
- A negative reading is rejected.
- An increase above the centralized large-jump threshold requires confirmation.

Event time, creation time, and update time are stored separately so later refuel/service/history features can handle historical records correctly.

Refuels always create or update one linked odometer entry with `source_type = REFUEL` and `source_record_id = refuels.id`. Expenses and income create a linked odometer entry only when the user supplies an odometer value. Editing a record updates that linked entry rather than inserting duplicates. Deleting a transactional record removes only the odometer row owned by that source record.

Manual odometer entries remain independent. Unified activity queries show manual odometer entries, but linked refuel/expense/income odometer rows are represented by their owning records to avoid duplicate activity.

## Money And Fuel Precision

Persisted money uses integer minor units. The current default presentation is GBP, so `42.75` is stored as `4275` pence. Currency parsing and formatting are centralized in `core/utilities/money.dart` so future currency settings can replace the default without hunting through widgets.

Fuel volume is stored as integer millilitres. This keeps litre input decimal-friendly while avoiding display-formatted strings as data.

Fuel unit price is stored as integer micros of the major currency unit per litre. For GBP, `1.397 GBP/L` is stored as `1397000`. UK pence-per-litre input converts by the same canonical value, so `139.7 p/L` and `£1.397/L` are equivalent and cannot be mistaken for `£139.70/L`.

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

## Financial Aggregation

Vehicle spending is currently:

`refuel spending + standalone expenses`

Income is not included in spending. Refuels do not generate standalone expense rows, so a refuel is counted once. Service spending will be added by the later service milestone using the same no-duplication rule.

Month spending uses `event_datetime` and the user's local calendar month, not `created_at`.

## Dependency Decisions

- `sqflite` is the mature mobile SQLite package used for Android persistence.
- `sqflite_common_ffi` is used in tests and keeps the database layer compatible with future Windows work.
- `provider` keeps app state lightweight and understandable for this milestone.
- No routing package was added because the current navigation is small and imperative routes keep the dependency surface lower.
- No analytics, telemetry, sync, account, or cloud packages are included.
