# DriveTracker

DriveTracker is a local-first Flutter application for managing vehicles and mileage. Milestone 1 establishes the production foundation, the vehicle core, and odometer tracking without accounts, telemetry, cloud APIs, or fabricated dashboard data.

## Current Milestone

Implemented in Milestone 1:

- Material 3 app shell with Home, Insights, central add action, Reminders, and More.
- First-run flow from welcome screen to adding the first vehicle.
- SQLite schema version 1 with controlled migrations.
- Vehicle creation, editing, listing, switching, and archiving.
- Multiple active vehicles with persisted selected vehicle.
- Odometer entries with manual readings and historical lower-reading confirmation.
- Home dashboard backed by stored vehicle and odometer data.
- Settings foundation for system, light, and dark theme preferences.
- Unit and widget tests for vehicle, odometer, persistence, and important UI flows.

Deferred to later milestones:

- Refuelling, servicing, expenses, income, documents, reminders engine, notifications, charts, exports, backup/restore, sync, accounts, OCR, and external vehicle integrations.

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
- `lib/features/home`: dashboard data contract and Home UI.
- `lib/features/insights`, `lib/features/reminders`, `lib/features/more`, `lib/features/settings`: milestone screens and settings foundation.
- `lib/shared/widgets`: reusable DriveTracker UI components used by current screens.

Presentation widgets do not issue raw SQL. Business rules live in validators and services so they can be tested outside widgets.

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

DriveTracker is local-first. Milestone 1 stores vehicle and odometer data in a local SQLite database on the device. It does not require login, internet access, analytics SDKs, advertising SDKs, or cloud sync.

## Roadmap Summary

Next milestones can add refuelling, service records, expenses, reminders, richer history, charts, exports, documents, backup/restore, and optional integrations. These should build on the existing repository/service boundaries and schema migration path rather than replacing user data.
