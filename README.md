# Zairza Attendance

Flutter Android app and read-only attendance API for Zairza club leadership. The existing ESP32 → Apps Script → Google Sheets writer is preserved.

The app provides recorded inside-now presence, searchable members, profiles, visits and raw scan history, date filters, source freshness, attendance anomaly notes, and encrypted local cached data. Access uses a separate revocable code per leader. Firebase and Google login are not used.

## Run the backend locally

Requires Node.js 24 LTS (the Docker image pins this major version).

```sh
cd services/api
npm ci
npm run build
npm start
```

The default is explicitly labeled sample mode, with the development-only access code `zairza-demo`. Do not use that code for live data. See [API configuration](services/api/README.md) for live mode.

## Run Flutter

```sh
cd apps/mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080
```

For a USB device/emulator, forward the local API first:

```sh
adb reverse tcp:8080 tcp:8080
```

The app accepts a server URL and leadership code at sign-in. Release builds require HTTPS; debug builds also allow loopback/emulator host addresses. The backend must be running for the local demonstration.

## Deploy

The owner deploys the backend to Render using [render.yaml](render.yaml). Follow the [Render deployment guide](docs/render-deployment.md) to create personal codes, configure the sheet, and connect the app. No source sharing or Apps Script deployment changes are performed automatically.

The supplied sheet is currently link-readable. `public-sheet` mode supports that existing access. For a private sheet, `sheets` mode supports service-account Viewer access. App authorization does not override Google Sheet sharing permissions.

## Project map

| Path | Purpose |
|---|---|
| apps/mobile | Flutter app and widget/client tests |
| services/api | TypeScript API, source adapters, domain rules, tests, Dockerfile |
| packages/contracts/openapi.json | API response and endpoint contract |
| firmware/esp32/Zairza_Workinginprocess | Original ESP32 sketch, byte-for-byte preserved |
| integrations/apps-script/attendance-logger | Supplied writer source, unchanged |
| tests/fixtures | Original sample records |
| docs | Data rules, deployment, builds and verification |

See [attendance rules](docs/data-rules.md), [Android builds](docs/android-builds.md), and [verification](docs/verification.md). Source data remains in Google Sheets. There are no attendance write endpoints.
