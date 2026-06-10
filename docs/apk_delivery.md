# APK Delivery Guide

This document explains how to build, verify, and deliver the release APK for the Flutter BLE/GPS gas surveyor app.

Use this guide only after the quality-checker has returned:

```text
QUALITY_PASS
```

---

## 1. Release APK Only

This project delivers only the release APK unless explicitly requested otherwise.

Build command:

```bash
flutter build apk --release
```

Expected output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

---

## 2. Pre-Build Checklist

Before building, confirm:

```text
- CLAUDE.md exists
- pubspec.yaml has the intended version
- CHANGELOG.md is updated for completed meaningful changes
- quality-checker returned QUALITY_PASS
- no Blocker or High issues remain
- Android signing files/secrets are available locally if release signing is configured
```

Do not build an APK if quality has not passed.

---

## 3. Required Commands

Run commands in this exact order:

```bash
flutter --version
flutter clean
flutter pub get
flutter build apk --release
```

`flutter clean` is required before release builds to avoid stale debug/native build artifacts.

APK builds can take several minutes. Wait for the final success or failure output.

---

## 4. Verify APK Exists

After the build succeeds, verify the release APK file exists:

```bash
ls -lh build/app/outputs/flutter-apk/app-release.apk
```

If the file is missing, the delivery is not complete.

---

## 5. Optional Copy to Delivery Folder

Optional folder structure:

```text
dist/
  apk/
    app-release-v<version>.apk
```

Always create the folder before copying:

```bash
mkdir -p dist/apk
cp build/app/outputs/flutter-apk/app-release.apk dist/apk/app-release.apk
```

If the app version is clear from `pubspec.yaml`, you may rename it manually:

```text
app-release-v1.1.0+2.apk
```

Do not invent a version number.

If copying to `dist/` fails but the APK exists at the default output path, the build itself is still successful.

---

## 6. Failure Classification

### Environment failure

Use `APK_ENV_BLOCKED` when the build fails because of the local machine, toolchain, or secrets:

```text
- Flutter SDK unavailable
- Android SDK missing
- Java/JDK missing or incompatible
- Gradle daemon/cache issue
- network dependency download failure
- filesystem permission issue
- missing Android signing configuration
- missing key.properties
- missing .jks keystore
- invalid signing passwords
```

Signing files and passwords are environment/secrets, not app code.

Note: If release signing is not yet set up for this project, configure a local keystore/signing setup first. If you only need a temporary installable build for manual testing, explicitly instruct the orchestrator to build a debug APK instead of using this release-only delivery flow.

Action:

```text
Fix the environment/signing setup, then rerun the APK builder.
Do not send environment or signing failures to the coder.
```

### Project build failure

Use `APK_BUILD_FAILED` when the build fails because of project code or configuration:

```text
- Dart compilation error
- broken imports
- missing asset declared in pubspec.yaml
- Android manifest/config issue
- dependency conflict caused by project config
```

Action:

```text
Send the failure summary back to the coder.
```

---

## 7. APK Build Report

After every APK build attempt, write or update:

```text
APK_BUILD_REPORT.md
```

Required format:

```markdown
# APK Build Report

## Status
APK_BUILD_DONE / APK_BUILD_FAILED / APK_ENV_BLOCKED

## Build Command
flutter clean
flutter pub get
flutter build apk --release

## APK Path
build/app/outputs/flutter-apk/app-release.apk

## App Version
<version from pubspec.yaml or unknown>

## Timestamp
<local timestamp>

## Notes
- <short notes only>
```

---

## 8. Manual Phone Testing

After receiving the APK, install it on the test phone and check:

```text
- app opens without crashing
- BLE scan works
- BLE connection works
- live methane/ethane values display correctly
- GPS/location updates work
- measurement start/pause/stop works
- readings log only while measurement is active
- CSV/export behavior works
- alarm behavior works
```

If a bug is found, report it with:

```text
APK version:
Phone model:
Android version:
Steps to reproduce:
Expected result:
Actual result:
Screenshot/video/logcat if available:
```

---

## 9. Delivery Rule

Final delivery is valid only when:

```text
APK_BUILD_DONE
APK file exists at build/app/outputs/flutter-apk/app-release.apk
Manual phone testing has been completed or explicitly deferred
```
