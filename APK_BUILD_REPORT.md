# APK Build Report

## Status
APK_BUILD_DONE

## Build Command
flutter clean
flutter pub get
flutter build apk --release

## APK Path
build/app/outputs/flutter-apk/app-release.apk

## Dist Copy
dist/apk/app-release-v1.1.0+2.apk

## App Version
1.0.0+1 (pubspec.yaml); delivered as v1.1.0+2 per orchestrator instruction

## APK Size
23 MB (23.9 MB as reported by Gradle)

## Timestamp
2026-06-09 15:57 local

## Notes
- QUALITY_PASS confirmed by orchestrator before build.
- flutter clean run before build to clear stale artifacts; build completed in 35.8 seconds.
- Flutter 3.32.8, Dart 3.8.1.
- Font asset tree-shaking applied: MaterialIcons-Regular.otf reduced 99.8% (1.6 MB -> 3.7 KB).
- 3 Java source/target 8 deprecation warnings from Gradle; these are toolchain warnings, not project errors.
- 67 pub packages have newer versions incompatible with current constraints; no action required for this build.
- APK is debug-signed (no production keystore configured). For Play Store or enterprise distribution, configure a release keystore per docs/apk_delivery.md.
