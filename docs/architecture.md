# DriveTracker Architecture

## Foundation

DriveTracker is structured around small feature modules. UI screens depend on `DriveTrackerController`, which coordinates repositories and services. Repositories centralize SQLite access. Services own cross-table behavior and domain rules.

The app intentionally avoids a heavy architecture framework for Milestone 1. `provider` and `ChangeNotifier` are enough for predictable state updates across add/edit/archive/select/update flows.

## Database

Schema version: `1`

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
  - `source_type` currently supports `MANUAL` and is shaped for future refuel/service/expense sources.
- `app_settings`
  - Key/value settings for selected vehicle and theme preference.

Foreign keys are enabled on database open. Indexes support active vehicle filtering and per-vehicle odometer lookup.

## Migrations

`DatabaseMigrations` owns schema creation and future upgrades. The app opens SQLite with `schemaVersion = 1` and an `onUpgrade` loop intended for V1 -> V2 -> V3 migrations. Future changes should add explicit migration steps instead of dropping and recreating user tables.

## Odometer Semantics

Odometer readings are stored as whole integer distance units, matching real-world odometers and avoiding decimal rounding problems. Each vehicle defines whether those units are miles or kilometers.

The current odometer is derived from the highest valid reading for that vehicle:

- A normal increase is accepted.
- A lower reading requires deliberate historical-entry confirmation.
- A lower historical entry does not rewind current odometer.
- A negative reading is rejected.
- An increase above the centralized large-jump threshold requires confirmation.

Event time, creation time, and update time are stored separately so later refuel/service/history features can handle historical records correctly.

## Dependency Decisions

- `sqflite` is the mature mobile SQLite package used for Android persistence.
- `sqflite_common_ffi` is used in tests and keeps the database layer compatible with future Windows work.
- `provider` keeps app state lightweight and understandable for this milestone.
- No routing package was added because the current navigation is small and imperative routes keep the dependency surface lower.
- No analytics, telemetry, sync, account, or cloud packages are included.
