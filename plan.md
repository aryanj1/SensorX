# blu — 4-Week Development Plan

## Context

The current app (`lib/main.dart`, 1061 lines, monolithic) is a working BLE scanner prototype that logs methane/ethane readings to per-session CSV files. The task list requires a full restructuring into a **Survey → Measurement → Data** field tool for gas surveyors. This is effectively a rewrite that reuses the BLE, GPS, map, and alarm logic while building a new data model, navigation structure, and feature set on top.

---

## Critical Constraints & Gaps You Must Know

### 1. iOS Background BLE — Hard OS Limitation
Apple **does not allow** continuous BLE scanning in the background. The existing `Info.plist` has `bluetooth-central` background mode, which lets an already-connected device continue sending notifications briefly, but:
- The app cannot actively scan for new devices in background
- iOS may suspend data logging after a few minutes if the app is not in the foreground
- **Recommendation:** For iOS, background operation means "alarms still fire and GPS updates if app is briefly backgrounded." True continuous background logging on iOS is not reliably achievable without Apple special entitlements. Field workers should keep the app in foreground during surveys.
- On Android this works fully via a Foreground Service.

### 2. DVGW Leak Classification
Placeholder categories (`Class 1 / 2 / 3`) will be used until you provide the real DVGW categories. **Provide these before Week 2 starts.**

### 3. Additional Alarm Sounds
Only `assets/alert.mp3` exists. You must **provide additional MP3 files** to support alarm sound selection in Week 4.

### 4. Flutter SDK Constraint
`pubspec.yaml` currently says `sdk: ">=2.18.0 <3.0.0"`. Several new packages require Dart 3. The SDK constraint will be updated to `">=3.0.0 <4.0.0"` — this is safe, existing packages are already compatible.

### 5. Upload / Export Destination
No backend upload is in scope. "Pending files" stays local. Export = ZIP via share sheet (email, AirDrop, etc.).

### 6. APK Delivery Workflow
A `docs/apk_delivery.md` file will document the `flutter build apk --release` + SharePoint steps. SharePoint setup itself is your responsibility.

---

## New Folder Structure

```
lib/
  main.dart                        # runApp only (~5 lines)
  app.dart                         # MaterialApp, theme, routing

  models/
    survey.dart                    # Survey (id, name, surveyor, created_at, device_id)
    measurement.dart               # Measurement (id, survey_id, name, status, started_at, stopped_at)
    reading.dart                   # Sensor reading row
    leak_mark.dart                 # Leak (measurement_id, gps, classification, notes, media_paths)
    note.dart                      # Note (measurement_id, text, gps, timestamp, media_paths)
    media_file.dart                # Media attachment (path, type, gps, timestamp)

  services/
    database_service.dart          # sqflite: schema + all CRUD
    ble_service.dart               # BLE scan + connect (extracted from main.dart)
    location_service.dart          # GPS stream (extracted from main.dart)
    alarm_service.dart             # Audio + vibration (extracted from main.dart)
    export_service.dart            # CSV build + ZIP + share sheet
    background_service.dart        # Android foreground service wrapper
    settings_service.dart          # SharedPreferences: alarm prefs, thresholds, map zoom

  screens/
    home/
      home_screen.dart             # Survey list + BLE device scanner
    survey/
      survey_screen.dart           # Survey detail: measurement list
      create_survey_screen.dart    # New survey form (name, surveyor)
    measurement/
      measurement_screen.dart      # Active measurement: map + live data + controls
    settings/
      settings_screen.dart         # Alarm sounds, thresholds, bargraph scale, map zoom
    files/
      pending_files_screen.dart    # (existing PendingFilesPage, moved)
      csv_preview_screen.dart      # (existing CsvPreviewPage, moved)
    help/
      help_screen.dart             # In-app help + support email button

  widgets/
    sensor_bargraph.dart           # Methane/ethane live bar display
    map_view.dart                  # Map with path, leak markers, position dot
    alarm_controls.dart            # Alarm toggle + threshold slider widget
    measurement_card.dart          # Measurement list tile with status indicator
```

---

## New Packages to Add

```yaml
sqflite: ^2.4.0                    # Survey/measurement/reading storage
shared_preferences: ^2.3.0         # Settings persistence
image_picker: ^1.1.0               # Photo + video capture
flutter_archive: ^6.0.4            # ZIP creation
share_plus: ^10.0.0                # Share sheet (email, AirDrop)
flutter_background_service: ^5.1.0 # Android foreground service
url_launcher: ^6.3.0               # Email support link in Help screen
package_info_plus: ^8.0.0          # Read app version for Settings screen
```

Keep all existing packages. Update SDK constraint to `>=3.0.0 <4.0.0`.

---

## Data Model

```
Survey
  id, name, surveyor_name, created_at, device_id?, device_name?

Measurement
  id, survey_id, name, status (idle / active / paused / stopped)
  started_at?, stopped_at?

Reading
  id, measurement_id, gps_utc, error_code
  methane_ppm, ethane_ppm, latitude, longitude

LeakMark
  id, measurement_id, timestamp, latitude, longitude
  classification (DVGW — placeholder), notes?, media_paths (JSON array)

Note
  id, measurement_id, text, timestamp, latitude, longitude, media_paths?

MediaFile
  id, measurement_id, path, type (photo / video), timestamp, latitude, longitude
```

### CSV Schema (per survey, one file)
```
GPS UTC, Measurement Name, Error Code, Methane (ppm), Ethane (ppm), Latitude, Longitude
```
Leak marks → `leaks.csv`. Notes → `notes.csv`. All bundled in the ZIP.

---

## Week-by-Week Plan

---

### Week 1 — Survey & Measurement Framework (Prio A)

**Goal:** Replace session-based model with Survey → Measurement → Data hierarchy.

| # | Task | Details |
|---|------|---------|
| 1 | Restructure project | Split monolithic `main.dart` into folder structure above. Extract BLE → `BleService`, GPS → `LocationService`, alarm → `AlarmService`. |
| 2 | Database setup | `DatabaseService` using sqflite. Tables: Survey, Measurement, Reading. Full CRUD methods. |
| 3 | Home screen redesign | List of surveys. "New Survey" opens `CreateSurveyScreen` (name + surveyor). Surveyor name shown on home screen (default: "Not Defined"), persisted via SharedPreferences. BLE scanner as a modal/panel. |
| 4 | Survey screen | Lists measurements for a survey. "New Measurement" button. Each measurement shows name + status badge (idle/active/paused/stopped). |
| 5 | Measurement screen | Start / Pause / Stop controls. Readings only log to DB when status is `active`. Map, live sensor view, and alarm controls live here. |
| 6 | CSV output | `ExportService.buildCsv(surveyId)` — one CSV per survey, all measurements, with `Measurement Name` column. Named `survey_{name}_{date}.csv`. |

**Files touched:** All of `lib/` (restructure). `pubspec.yaml`. No platform config changes yet.

---

### Week 2 — Media, Notes & Leak Marking (Prio A)

**Goal:** Enrich measurements with photos, videos, notes, and leak marks.

| # | Task | Details |
|---|------|---------|
| 1 | Photo + video capture | `image_picker` package. Toolbar buttons on `MeasurementScreen`: Photo, Video. Each saved with GPS + UTC. Files stored in `getApplicationDocumentsDirectory()/survey_{id}/measurement_{id}/`. |
| 2 | Notes | "Note" toolbar button → text input dialog. Saves `Note` to DB with GPS + timestamp. |
| 3 | Mark Leak | "Mark Leak" button → records GPS + timestamp immediately → bottom sheet for classification (DVGW placeholder), optional notes + media. Saves `LeakMark` to DB. |
| 4 | Leak map markers | `MapView` shows leak positions as red pin icons, distinct from custom tap-markers. |
| 5 | ZIP export | `ExportService.exportSurvey(surveyId)`: CSV + notes.csv + leaks.csv + all media → `.zip` via `flutter_archive` → share sheet via `share_plus`. |
| 6 | New permissions | Android: `CAMERA`, `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`. iOS Info.plist: `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryUsageDescription`. |

---

### Week 3 — Map Features & Background Operation (Prio B/C)

**Goal:** Walking path on map, background logging on Android.

| # | Task | Details |
|---|------|---------|
| 1 | Walking path | `MeasurementScreen` accumulates `List<LatLng>` while active. `MapView` draws it as a `PolylineLayer` (dark red = current measurement). |
| 2 | Other measurements' paths | `MapView` loads path points for all measurements in same survey from DB. Toggle checkbox shows/hides them in light red/pink. |
| 3 | Background service (Android) | `BackgroundService` wraps `flutter_background_service`. Starts Foreground Service on measurement `active`, keeps BLE + DB logging alive when app backgrounded or screen off. Stops on measurement `stopped`. iOS: best-effort via existing `bluetooth-central` mode — limitation noted in Help screen. |
| 4 | Map zoom in Settings | `SettingsScreen` adds "Default Map Zoom" slider (10–20). `MapView` reads it on init via `SettingsService`. |

**Files touched:** `map_view.dart`, `measurement_screen.dart`, `background_service.dart`, `settings_screen.dart`, `settings_service.dart`.

---

### Week 4 — Polish, Housekeeping & Documentation (Prio B/C)

**Goal:** Settings, versioning, help screen, APK workflow.

| # | Task | Details |
|---|------|---------|
| 1 | Alarm sound selection | Add MP3s to `assets/sounds/`. `SettingsScreen` lists sounds with "Preview" button. Selection saved via `SettingsService`. `AlarmService` reads selected path. |
| 2 | Bargraph display | `SensorBargraph` widget: animated horizontal bar for methane + ethane. `SettingsScreen` adds min/max scale inputs per gas. Scales read from `SettingsService`. |
| 3 | Version numbering | `pubspec.yaml` version → `1.1.0+2`. Add `CHANGELOG.md`. Settings screen footer shows version via `package_info_plus`. |
| 4 | In-app Help screen | `HelpScreen` describes main functions. "Contact Support" button launches `mailto:support@sensorXsolutions.com` via `url_launcher`. |
| 5 | APK delivery docs | `docs/apk_delivery.md`: `flutter build apk --release`, signing config steps, SharePoint upload instructions. |
| 6 | Multi-param home (stretch) | Home screen card: Methane, Ethane, Flow — shows "Not Connected" where unavailable. |

**Files touched:** `settings_screen.dart`, `alarm_service.dart`, `sensor_bargraph.dart`, `help_screen.dart`, `pubspec.yaml`, `assets/sounds/`.

---

## What I Can Do vs. What You Must Provide

| Area | Who | Notes |
|------|-----|-------|
| All Dart/Flutter code | Me | Models, services, screens, widgets, exports, permissions |
| DVGW leak categories | **You** | Provide exact category names before Week 2 |
| Additional alarm sound files | **You** | Provide MP3s for `assets/sounds/` before Week 4 |
| iOS background logging | **You (inform users)** | Keep app in foreground during surveys on iPhone |
| APK signing keystore | **You** | Generate + manage your own keystore |
| SharePoint folder setup | **You** | I document the steps, you set it up |
| BLE UUID changes | **You (inform me)** | If hardware UUIDs change, update `ble_service.dart` |
| Flow meter integration | Out of scope | Deferred to next cycle |

---

## Verification Plan

| Week | How to verify |
|------|--------------|
| 1 | Create survey → add measurement → start/pause/stop → confirm readings only appear when active → export CSV → confirm `Measurement Name` column present |
| 2 | Take photo + add note during active measurement → mark a leak → export ZIP → confirm CSV + media + notes.csv + leaks.csv all present |
| 3 | Walk 50 m with active measurement → confirm polyline on map → background app on Android → confirm readings continue → toggle other-measurement paths |
| 4 | Change alarm sound → trigger alarm → confirm new sound plays → adjust bargraph scale → confirm bar updates → open Help → tap Contact Support → confirm email client opens |

---

