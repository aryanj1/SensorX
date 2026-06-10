# CLAUDE.md — blu (BLE/GPS Gas Surveyor)

## Project Purpose
Flutter app for field gas surveying. Connects to a BLE methane/ethane sensor, logs GPS-stamped readings, supports leak marking, notes, media capture, and ZIP export. Being restructured from a monolithic `lib/main.dart` into a Survey → Measurement → Data architecture.

## Architecture Rules
- `main.dart` calls `runApp` only — no logic, no widgets beyond the app entry point.
- `app.dart` owns `MaterialApp`, theme, and routing.
- Business logic lives in `services/`. UI lives in `screens/` and `widgets/`. Data shapes live in `models/`.
- Never put business logic back into `main.dart` or directly into screen widgets.
- Folder layout: `lib/models/`, `lib/services/`, `lib/screens/`, `lib/widgets/`. See `plan.md` for the full file tree.

## Product Rules
- A **Survey** contains one or more **Measurements**. A **Measurement** has a status: `idle / active / paused / stopped`.
- Sensor **Readings** are only logged to the database when a measurement is `active`.
- CSV export: one file per survey, all measurements combined, with a `Measurement Name` column.
- CSV columns: `GPS UTC, Measurement Name, Error Code, Methane (ppm), Ethane (ppm), Latitude, Longitude`.
- Leak marks, notes, and media are stored separately and bundled into a ZIP on export alongside the CSV.
- Surveyor name persists on the home screen (default: "Not Defined") via `SettingsService`.
- BLE service UUID: `4fafc201-1fb5-459e-8fcc-c5c9c331914b`. Characteristic UUID: `beb5483e-36e1-4688-b7f5-ea07361b26a8`. Update in `services/ble_service.dart` if hardware changes.

## Scope — Out of Scope for This Cycle
- Bluetooth Flow Meter integration
- Customised leak reports (e.g. Westnetz template)
- Loading / browsing past surveys from history
- Alarm 2
- GIS / Trimble Connect integration

## External Inputs Required (Not in Codebase)
- **DVGW leak classification categories** — use placeholders (`Class 1 / 2 / 3`) until the real categories are provided.
- **Additional alarm sound files** — MP3s must be supplied and placed in `assets/sounds/` before alarm sound selection (Week 4) is implemented.

## Platform Rules
- **Android background logging:** use a Foreground Service via `flutter_background_service`. Logging and alarms must continue when the app is backgrounded or the screen is off.
- **iOS background BLE/GPS:** best-effort only via the existing `bluetooth-central` background mode in `Info.plist`. Continuous logging is not guaranteed; field workers on iPhone must keep the app in the foreground during active surveys. Document this limitation in the in-app Help screen.

## Quality Gates
Before marking any feature complete, run in order:
1. `dart format --set-exit-if-changed .`
2. `flutter analyze`
3. `flutter test`
4. `flutter build apk --debug`

Release builds use `flutter build apk --release`. Do not build a release APK if Blocker or High severity issues remain from `flutter analyze`.

## Workflow
- **New feature:** plan → implement → quality gates → APK.
- **Bug fix:** reproduce → fix → quality gates → APK.
- Maximum 3 fix loops per issue before escalating to the user.
- Inspect the relevant file(s) before editing — do not assume structure.

## Documentation Rules
- Update `CHANGELOG.md` only after a meaningful, completed change — not mid-task.
- APK build and SharePoint distribution steps go in `docs/apk_delivery.md`.
- Never store secrets, keystores, or credentials in the repository.

## Style Rules
- Use exact file paths and shell commands in responses.
- Preserve working BLE, GPS, and alarm behaviour unless the change is an intentional refactor.
- Keep responses direct; skip restating what the code already makes obvious.
