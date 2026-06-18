# APK Build Report

## Status
APK_BUILD_DONE

## Build Command
flutter clean
flutter pub get
flutter build apk --debug

## APK Path
build/app/outputs/flutter-apk/app-debug.apk

## App Version
1.0.0+1

## File Size
99 MB

## Timestamp
2026-06-18 12:18:48–12:19:11 CEST (~23 seconds)

## Notes
- Debug build explicitly requested by orchestrator for GPS path filtering + path rendering + path restore feature verification.
- APK verified at default output path.
- Warnings (non-blocking):
  - Android x86 target support will be removed after Flutter 3.27 stable.
  - Javac: source/target value 8 obsolete (3 warnings); suppressible with -Xlint:-options.
  - 85 pub packages have newer versions incompatible with current constraints.
- No errors. No Dart compilation failures.
