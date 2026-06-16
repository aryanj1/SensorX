# Changelog

All meaningful completed changes to this Flutter BLE/GPS gas surveyor app will be documented here.

Format follows: Added, Changed, Fixed, Known Issues.

## Unreleased

### Added
- `LeakMark` model (`lib/models/leak_mark.dart`): `id`, `measurement_id`, `timestamp`, `latitude?`, `longitude?`, `note?`, `media_path?` — with `fromMap`/`toMap`.
- `DatabaseService` v5: new `leak_marks` table with `ON DELETE CASCADE` on `measurement_id`. DB v4→v5 migration adds the table without touching existing data. New methods: `insertLeakMark`, `getLeakMarksForMeasurement`, `getLeakMarksForSurvey`, `deleteLeakMark`.
- Mark Leak FAB (warning icon) on Record/Map screen: fifth circular button in the right-edge FAB stack. Active only when measurement status is `active`; shows SnackBar "Start a measurement to mark a leak." otherwise. Bottom sheet accepts an optional note and optional photo attachment. Saves `LeakMark` to SQLite with current GPS (null-safe if GPS unavailable). Shows SnackBar "Leak marked" on success.
- Leak location markers on the map: each saved leak mark with valid GPS is rendered as an orange `Icons.warning_amber_rounded` pin (`MarkerLayer`) on the flutter_map view. Markers reload automatically when switching measurements via `activateMeasurement()` and are cleared on New Recording.
- Updated `ExportService.exportSurveyZip`: main survey CSV now has 10 columns (`GPS UTC, Measurement Name, Error Code, Methane (ppm), Ethane (ppm), Latitude, Longitude, notes, media_exists, leak_marked`). ZIP additionally includes `notes.csv` (if notes exist), `media.csv` (if media exists), and `leak_marked.csv` (if leak marks exist). Media files inside the ZIP are copied with safe export names (`{survey}_{measurement}_{timestamp}_{type}_{index}.{ext}`) — original on-disk files are not renamed. `buildCsv` (legacy 7-column CSV share) is unchanged.

### Fixed
- BLE connected-device row in `BLEScannerScreen` (`_buildConnectedDeviceSection`) no longer blinks and disappears due to transient BLE stream events during scan start/stop. Guard changed from `!isConnected` to `!isConnected && !device.isConnected` so a spurious `disconnected` stream event does not hide the row while the device remains physically connected.
- "Go to BLE" navigation from the no-device measurement alert now uses `Navigator.popUntil(isFirst)` before pushing `BleScanWaitScreen`, so pressing Back from the BLE page after connecting returns to `HomeScreen` (surveyor list) instead of the Record/Map screen.
- Record/Map live record panel no longer displays elapsed time. Only Methane (CH₄) and Ethane (C₂H₆) values are shown. Timestamp logging to SQLite and CSV export are unaffected.
- BLE scanning toggle OFF now calls `device.disconnect()` on the current app-connected device and clears `BleState.currentDevice` / `BleState.currentCache` — sensor no longer stays connected in the background after the user turns the toggle off.
- Connected device row in `BLEScannerScreen` now shows a small X (`Icons.close`) next to the green check icon. Tapping X disconnects only that device, leaves the scanning toggle ON, and keeps the available-devices list visible.
- Measurement Start and New Recording buttons on the Record/Map screen are now blocked when `BleState.currentDevice?.isConnected` is false. An AlertDialog ("No device connected. Please connect a sensor before starting a measurement.") is shown; confirming "Go to BLE" navigates to `BleScanWaitScreen`.

### Added
- BLE scan wait screen wait reduced from 10 s to 7 s before navigating to device list.
- BLE scan wait screen (`lib/screens/ble/ble_scan_wait_screen.dart`): intermediary screen shown when BLE icon is tapped on HomeScreen. Full-screen deep red/dark gradient, bold white "Starting to Scan for Bluetooth Devices" text, `CircularProgressIndicator`. Requests BLE/location permissions then waits exactly 10 seconds before navigating (pushReplacement) to `BLEScannerScreen`. Back-safe: timer cancelled in `dispose`, `mounted` guard prevents post-dispose navigation.
- BLE devices screen restyled: `BLEScannerScreen` now uses iOS Bluetooth-settings aesthetic — dark `Color(0xFF1C1C1E)` background, "MY DEVICES" section header, rounded dark card rows (`Color(0xFF2C2C2E)`, radius 12) with device name in white, "Not Connected" label in grey, info icon. `StreamBuilder<bool>` scanning toggle at top wired to `FlutterBluePlus.isScanning`. All connect/scan/pending-file logic unchanged.
- Splash / landing screen (`lib/screens/splash/splash_screen.dart`): branded full-screen gradient (black → deep red `0xFF6B0000`) with "SENSOR X SOLUTIONS" logotype. "X" is drawn in pure Flutter — two overlapping rotated `Container`s (red stroke on top, grey underneath). Loading bar (`LinearProgressIndicator`, height 3, red) fills over exactly 10 seconds then auto-navigates to `HomeScreen` via `Navigator.pushReplacement` (back button cannot return to splash). `AnimationController` is properly disposed; `mounted` guard prevents post-dispose navigation.
- Surveyor Workspace UI polish: red accent headers, rounded cards (radius 14, elevation 3), bold measurement/survey names. `CircleAvatar` on surveyor cards uses red background. "Surveyors" and "Measurements" headings use `colorScheme.onSurface` (white in dark theme) rather than red. Dark/light theme compatible.
- `Note` model (`lib/models/note.dart`): `id`, `measurementId`, `text`, `createdAt` — with `fromMap`/`toMap`.
- `DatabaseService` v4: new `notes` table with `ON DELETE CASCADE` on `measurement_id`. DB v3→v4 migration adds the table without touching existing data. New methods: `insertNote`, `getNotesForMeasurement`, `deleteNote`.
- Record/Map screen gains four circular floating action buttons stacked on the right map edge (alarm, notes, photo, video), styled as translucent dark circles. Active overlay highlighted in red.
- Alarm/Threshold overlay panel on Record/Map: toggle alarm on/off, adjust threshold PPM via slider. Wired to existing `_alarmEnabled` / `_threshold` fields (changed from `final` to mutable). Panel is semi-transparent (`0xEE1a1a1a`) and does not cover the full map.
- Notes overlay panel on Record/Map: shows notes for the active measurement (DB-backed), add-note text field, per-note delete. Safe message shown when no measurement is active.
- Photo and video capture icons on Record/Map screen: reuse existing `image_picker` + `DatabaseService.insertMediaFile` logic from `MeasurementScreen`; gated on `_recordStatus == 'active'`.
- Measurement navigation re-routing: tapping a `MeasurementCard` in `SurveyScreen` (reached via the workspace Surveys tab) now calls a callback that switches to the Record/Map tab and pre-loads the selected measurement via `GlobalKey<RecordMapTabState>.activateMeasurement(m)` and `addPostFrameCallback`. `MeasurementScreen` push preserved as fallback when `onMeasurementSelected` is null (e.g. from `BLEScannerScreen`).
- `RecordMapTabState` made public to allow `GlobalKey<RecordMapTabState>` access from `SurveyorWorkspaceScreen`.
- UI polish: bold page headers added to Surveyors, Surveys, and Measurements list screens — "Surveyors" / "Surveys" / "Measurements" in `headlineSmall` bold, rendered above the list inside the body (loading and empty-state views unaffected).
- App renamed to "X-Survey" in all user-facing locations: `MaterialApp.title`, AppBar title on HomeScreen, `android:label` in AndroidManifest, `CFBundleDisplayName`/`CFBundleName` in Info.plist. Internal package name `blu` and all import paths unchanged.
- Week 2 Task 1: Photo/video capture during active measurements. `MeasurementScreen` gains Photo and Video buttons (visible when a measurement is selected) that call `image_picker` and are gated — tapping while not `active` shows a SnackBar; capture only triggers when status is `active`.
- `MediaFile` model (`lib/models/media_file.dart`): `id`, `measurementId`, `path`, `type` (photo/video), `timestamp`, `latitude?`, `longitude?` — with `fromMap`/`toMap`/`copyWith`.
- `DatabaseService` v3: new `media_files` table with `ON DELETE CASCADE` on `measurement_id`. DB v2→v3 migration adds the table without touching existing data. New methods: `insertMediaFile`, `getMediaFilesForMeasurement`, `getMediaFilesForSurvey`.
- Captured media stored at `{appDocumentsDir}/survey_{surveyId}/measurement_{measurementId}/` and linked to the correct measurement via `measurement_id` in SQLite.
- `ExportService.exportSurveyZip(surveyId)`: assembles a ZIP from the survey CSV + all media files + a `media.csv` metadata file using `flutter_archive`. ZIP filename: `survey_{name}_{YYYYMMDD}_{HHmmss}.zip`. Handles: readings-only (CSV-only ZIP), no data at all (error SnackBar), missing media files on disk (skipped gracefully).
- "Share ZIP" button (`Icons.archive_outlined`) added to `SurveyScreen` AppBar alongside the existing "Share CSV" button.
- Android permissions: `CAMERA`, `RECORD_AUDIO`, `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`.
- iOS usage descriptions: `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryUsageDescription`.
- Surveyor-first navigation (Home → Surveyors → Surveys → Measurements): `HomeScreen` now shows surveyor cards with a person icon instead of a direct survey list. New `SurveyorScreen` (`lib/screens/surveyor/surveyor_screen.dart`) lists surveys scoped to the selected surveyor.
- `Surveyor` model (`lib/models/surveyor.dart`) with `id`, `name`, `fromMap`/`toMap`/`copyWith`.
- `DatabaseService` v2: new `surveyors` table, `insertSurveyor`/`getAllSurveyors`/`getSurveysForSurveyor`/`deleteSurveyor` methods. `deleteSurveyor` uses a transaction to manually cascade to surveys → measurements → readings (required because `ALTER TABLE ADD COLUMN` cannot carry `ON DELETE CASCADE`).
- DB v1→v2 migration in `_onUpgrade`: creates `surveyors` table, adds `surveyor_id` FK column to `surveys`, back-fills from distinct `surveyor_name` values. Existing data is preserved; `NULL`/empty names default to `'Not Defined'`.
- Delete surveyors, surveys, and measurements — all with confirmation dialogs. Deleting a surveyor cascades to all child data.
- `Survey` model: added `surveyorId` field (nullable, backward-compatible with v1 rows).
- `MeasurementCard`: optional `onDelete` callback renders a delete icon button when provided.
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

### Added
- `lib/constants/sensor_facts.dart`: 50 methane/ethane sensor facts compiled from the reference fact sheet, stored as a compile-time `const List<String> kSensorFacts`.
- Splash screen (`lib/screens/splash/splash_screen.dart`): one random sensor fact is selected each launch using `dart:math Random` and displayed below the loading bar in white text (fontSize 13, fontWeight w300, 75% opacity). SensorX logo, SOLUTIONS text, gradient, and loading bar are unchanged.
- Real-time route polyline on Record/Map screen (`lib/screens/surveyor/record_map_tab.dart`): GPS positions are accumulated in `List<LatLng> _routePoints` during active measurement. A dark-red (`Color(0xFF8B0000)`) polyline (strokeWidth 4.0) is drawn on the map via `PolylineLayer` when two or more points exist. Pause stops accumulation but preserves the existing route; Resume continues from the last point; Finish/Stop freezes the route; New Recording clears it. Switching measurements via `activateMeasurement()` reloads the historical route from existing SQLite readings (latitude/longitude columns in the `readings` table) via a fire-and-forget `_loadRouteForMeasurement()` helper — no schema changes required.

### Fixed
- BLE scanner (`BLEScannerScreen`): scan results `StreamSubscription` (`_resultsSub`) is now stored and cancelled in `dispose()` — previously the listener leaked on every screen exit.
- BLE scanner: `_buildConnectedDeviceSection()` shows the already-connected device (from `BleState.currentDevice`) above the "AVAILABLE DEVICES" list when entering the BLE screen while a device is still connected. Section disappears automatically via `StreamBuilder<BluetoothConnectionState>` when the device disconnects externally.
- BLE button on `HomeScreen`: if `BleState.currentDevice?.isConnected` is true, tapping the Bluetooth button now navigates directly to `BLEScannerScreen` instead of showing the scan-wait intro screen. The wait screen is only shown when no device is connected.
- `BleScanWaitScreen` wait timer reduced from 7 s to 4 s.
- `SurveyorWorkspaceScreen` "● Connected" AppBar badge colour changed from white to green.
- Android native splash: `launch_background.xml` (drawable and drawable-v21) changed from white/`colorBackground` to `@android:color/black`; `LaunchTheme` parent changed to `Theme.Black.NoTitleBar` — eliminates the brief white/app-icon flash before the SensorX Solutions branded splash screen appears.
- BLE scanner (`BLEScannerScreen`): `foundDevices` list is now cleared when scanning stops (both via toggle and natural timeout via `StreamSubscription<bool>` on `FlutterBluePlus.isScanning`) — previously stale devices remained visible when scanning was off.
- BLE scanner: `_connectAndShowData` is now async and calls `device.connect()` before navigating to `MeasurementScreen`. A connecting dialog is shown during the attempt; failures show a SnackBar and prevent navigation. Previously tapping any discovered device navigated immediately without a BLE connection.
- BLE scanner: section header renamed "MY DEVICES" → "AVAILABLE DEVICES". Device subtitle shows real-time "Connected"/"Not Connected" state via `StreamBuilder<BluetoothConnectionState>`.
- Splash screen: "SENSOR X" logotype changed to white (was red). "SOLUTIONS" text gains a double white shadow glow matching the reference branding image.

### Changed
- Phase 0 structure-only refactor: split monolithic `lib/main.dart` into `lib/app.dart`, `lib/services/cache_service.dart`, and `lib/screens/` (home, measurement, files). `main.dart` now calls `runApp` only. Behavior unchanged (BLE/GPS/alarm/map/CSV preserved).
- Bumped Dart SDK constraint to `>=3.0.0 <4.0.0` (required for the installed Dart 3.8.1 toolchain).

### Fixed
- Replaced deprecated APIs surfaced by the SDK bump: `withOpacity` → `withValues`, `desiredAccuracy` param → `LocationSettings(accuracy:)`, removed dead null-aware on non-nullable `Position.timestamp`. No behavior change.

### Known Issues
- 