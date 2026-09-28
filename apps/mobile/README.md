# Zairza Flutter app

Android app for club leadership, using personal revocable access codes. Flutter 3.47.5 / Dart 3.13.4 were installed for this implementation.

```sh
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080
```

For local testing, run the API and `adb reverse tcp:8080 tcp:8080`. The sign-in screen accepts a Render HTTPS URL, so the release APK does not require a rebuild when the host changes.

Structure:

- lib/core/api.dart — authenticated HTTP requests, pagination, error mapping, HTTPS URL checks.
- lib/core/store.dart — session, lifecycle-aware refresh, encrypted storage, logout/revocation and stale state.
- lib/screens — leadership sign-in, inside/dashboard, directory, settings, profile/visits/raw scans.
- lib/core/format.dart — consistent Asia/Kolkata display.
- test — API and meaningful screen-state tests.

Foreground refresh runs every 30 seconds and on resume. Pull-to-refresh is available. Local credentials and the current account's cached attendance are held in platform secure storage; logout clears them. Android backup is disabled. Revocation is enforced on the next online API request; offline data cannot be remotely erased.

Attendance calculations live on the backend. Source mode (demo/live), source read time, stale results and data-quality notes remain visible. Profile date filtering affects history; top-level totals are explicitly all-time.

See [Android builds](../../docs/android-builds.md) for signing and [Render setup](../../docs/render-deployment.md) for the server.
