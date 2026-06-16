# APK Build Report

## Status
APK_BUILD_DONE

## Build Command
flutter clean
flutter pub get
flutter build apk --release

## APK Path
build/app/outputs/flutter-apk/app-release.apk

## Dist Path
dist/xsurvey-release-20260615-164153/app-release.apk

## App Version
1.0.0+1

## APK Size
25 MB

## Timestamp
2026-06-15 16:41:53 local

## Notes
- flutter clean run before build to clear stale artifacts (per standing rule).
- Build completed in ~41 seconds. Flutter 3.32.8, Dart 3.8.1.
- Font tree-shaking applied: MaterialIcons-Regular.otf reduced 99.6% (1.6 MB to 5.9 KB).
- 3 Java compiler warnings: source/target value 8 obsolete — Gradle/AGP toolchain warnings, not project code issues; safe to ignore until AGP is updated.
- 85 packages have newer versions incompatible with current dependency constraints; no action required for this build.
- APK is debug-signed (no production keystore configured). For Play Store or enterprise distribution, configure a release keystore per docs/apk_delivery.md.
- Bugs addressed in this build: BLE connected-state persistence on back-navigation; back-navigation after BLE connect lands on HomeScreen not Record/Map; live panel shows only CH4/C2H6 values with no time/elapsed display.
