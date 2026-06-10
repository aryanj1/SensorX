# Changelog

All meaningful completed changes to this Flutter BLE/GPS gas surveyor app will be documented here.

Format follows: Added, Changed, Fixed, Known Issues.

## Unreleased

### Added
- CSV share sheet (`share_plus: ^10.1.4`) — after export succeeds, native Android share sheet opens so the CSV can be sent to email, Google Drive, WhatsApp, etc. Export failures still show a SnackBar.
- Task 6: `ExportService.buildCsv(surveyId)` (`lib/services/export_service.dart`) — generates one CSV per survey combining all measurements' SQLite readings. Header: `GPS UTC,Measurement Name,Error Code,Methane (ppm),Ethane (ppm),Latitude,Longitude`. Filename: `survey_{safe_name}_{YYYYMMDD_HHmmss}.csv`. Saved to `getApplicationDocumentsDirectory()`. Throws plain string on empty survey; no raw SQL in service.
- Task 6: `SurveyScreen` — `Icons.download` AppBar button calls `ExportService.buildCsv` and shows file path (or error) in a `SnackBar`. No crash on empty survey.
- Task 6: `MeasurementScreen` UI fix — live BLE readings are now hidden when a measurement is `idle`, `paused`, or `stopped` (SQLite Survey Mode). Placeholder text shown: "Measurement is not active. Tap Start to begin displaying and logging readings." Legacy CSV Mode (no measurement selected) continues to show live readings unconditionally.
- Logged Values Screen (`lib/screens/measurement/measurement_readings_screen.dart`): read-only SQLite readings viewer for individual measurements. Accessible via a new `Icons.list_alt` icon button on each `MeasurementCard` (card tap → `MeasurementScreen` unchanged). Displays measurement name in AppBar, reading count header, and a scrollable list of rows (GPS UTC, CH4 ppm, C2H6 ppm, error code, lat, lng). Pull-to-refresh + AppBar refresh button. Empty state when no readings. Error state with Retry on DB failure or null measurement ID — no unhandled exceptions.
- `DatabaseService.getReadingCountForMeasurement(int measurementId)`: COUNT query returning the number of readings for a given measurement.
- Week 1 Task 5: `MeasurementScreen` now accepts an optional `Measurement` and wires lifecycle controls to SQLite. Start sets `status='active'` + `startedAt`; Pause sets `status='paused'`; Stop sets `status='stopped'` + `stoppedAt`. BLE readings are inserted into `DatabaseService` only when status is `active`; legacy CSV logging continues unconditionally. `device` and `cache` constructor params made nullable — screen shows a "No BLE device connected" banner and skips BLE connect/listen when no device is passed.
- `BleState` service (`lib/services/ble_state.dart`) — static holder for the current `BluetoothDevice` and `TTLFileCache`, set by the BLE scanner flow and read by `SurveyScreen` when opening a measurement.
- `SurveyScreen` — `MeasurementCard.onTap` now navigates to `MeasurementScreen` with the selected `Measurement` and refreshes the badge list on pop. Accepts optional `TTLFileCache? cache` passed through from `HomeScreen`.
- Home theme toggle — light/dark mode `IconButton` in `HomeScreen` AppBar, persisted via `SharedPreferences` key `theme_mode`. `App` uses a `static ValueNotifier<ThemeMode>` with `ValueListenableBuilder` so the entire app responds without a `StatefulWidget` rebuild.
- OSM tile policy — `TileLayer` in `MeasurementScreen` now sets `userAgentPackageName: 'com.sensorx.blu'`.
- Week 1 Task 4: `SurveyScreen` — real StatefulWidget replacing the "Coming soon" stub. Loads measurements for the selected survey from `DatabaseService`, shows each with a colour-coded status badge (idle=grey, active=green, paused=orange, stopped=red). FAB opens a "New Measurement" dialog with inline name validation; new rows inserted with `status = 'idle'`. Empty-state message when no measurements exist.
- `MeasurementCard` widget (`lib/widgets/measurement_card.dart`) — reusable list tile with `_StatusBadge` private helper using `statusFromString` to resolve the `MeasurementStatus` enum.
- Week 1 Task 3: `HomeScreen` — survey list from `DatabaseService`, surveyor name persisted via `SharedPreferences` (default "Not Defined", editable in-place), New Survey dialog with inline validation, stub `SurveyScreen`. BLE scanner accessible via AppBar icon.
- Week 1 Task 3: `SettingsService` (static, key `surveyor_name`). Added `shared_preferences: ^2.3.0`.
- Week 1 Task 2: `DatabaseService` (sqflite singleton, `blu_surveys.db` v1) with full CRUD for `surveys`, `measurements`, and `readings` tables. FK constraints with `ON DELETE CASCADE`; `PRAGMA foreign_keys = ON` applied on every open.
- Models: `Survey`, `Measurement` (with `MeasurementStatus` enum), `Reading` — each with `fromMap`/`toMap`/`copyWith` as appropriate. Safe `(num?)?.toDouble()` casting for all SQLite `REAL` columns.
- Added `sqflite: ^2.4.0` and `path: ^1.9.0` to dependencies.

### Changed
- Phase 0 structure-only refactor: split monolithic `lib/main.dart` into `lib/app.dart`, `lib/services/cache_service.dart`, and `lib/screens/` (home, measurement, files). `main.dart` now calls `runApp` only. Behavior unchanged (BLE/GPS/alarm/map/CSV preserved).
- Bumped Dart SDK constraint to `>=3.0.0 <4.0.0` (required for the installed Dart 3.8.1 toolchain).

### Fixed
- Replaced deprecated APIs surfaced by the SDK bump: `withOpacity` → `withValues`, `desiredAccuracy` param → `LocationSettings(accuracy:)`, removed dead null-aware on non-nullable `Position.timestamp`. No behavior change.

### Known Issues
- 