# Deploy the attendance API to Render

The owner will deploy this service. The API is a Node.js container; the Flutter app installs separately on Android. No Firebase or Google login is required. Leadership access uses independent, high-entropy, revocable bearer codes.

## 1. Create leadership access

From services/api, after npm ci:

```sh
npm run create-access -- president "Club President"
```

This prints a new accessCode and a leader object. Give the access code privately to that leader. Store ONLY the leader object on the server, in a JSON array named LEADERS_JSON. Create a different code per leader. The server stores SHA-256 hashes of randomly generated 192-bit codes, not plaintext passwords. Do not replace these codes with short PINs or predictable passwords.

Example structure (replace the placeholder hash using the command):

```json
[{"id":"president","name":"Club President","codeHash":"<64-character hash from generator>","active":true}]
```

## 2. Create Render service

Push the repository to your Git provider, then in Render choose New → Blueprint and select the repository to use render.yaml. Enter LEADERS_JSON when requested. Alternatively create a Web Service using Docker with Root Directory services/api, Dockerfile ./Dockerfile, and health path /health. No build/start command is required for the Docker service.

Choose the free instance for the initial pilot. The application reads Render's PORT automatically. Keep all leadership hashes and any service-account credentials in Render environment variables or secret files, never in Git.

| Variable | Value |
|---|---|
| DATA_MODE | public-sheet for the supplied, currently link-readable sheet; sheets for private service-account access |
| SPREADSHEET_ID | 1KKLk-9ZVf4M08IL4Zyu7-yI3lqF2zuIupd_WpAxSo5I |
| SHEET_TAB | Zairza Attendance |
| EXCLUDE_TEST_ROWS | true (excludes TEST registration and TEST- IDs) |
| LEADERS_JSON | JSON array of generated leader objects |

The supplied sheet was read successfully without Google credentials during development. App codes protect the API, but do not make that existing sheet private. No sharing permissions were changed. For private data, switch to the service-account method below and have the sheet owner restrict link sharing.

## 3. Verify and connect

Open https://YOUR-SERVICE.onrender.com/health; expect {"status":"ok"}. Health confirms the process is running, not that Sheets access is working. Enter the Render HTTPS URL and a leadership code in the app. Confirm the source says Google Sheets, inspect the last-refresh timestamp, and compare the directory/profile with the sheet. A fresh scan should appear on a normal foreground refresh.

Render Free sleeps after idle periods. First requests can fail or time out while it wakes; wait and retry. The app displays cached records explicitly as last known data. It does not run artificial keepalive traffic.

## 4. Revoke or replace access

Set a leader's active to false in LEADERS_JSON and redeploy/restart the service. Every subsequent request checks the active list; no app update is required. Online apps clear their saved session/data on the next rejected request. Offline devices can retain previously downloaded data until reconnecting or signing out; revocation cannot remotely erase an offline phone.

To rotate a code, generate a new code and replace that leader's hash. To add a leader, append a new generated object. Never share one code among all leaders. With LEADERS_FILE configured instead, the API reloads that file for every request, allowing immediate local revocation without restart.

## Private Google Sheet connection (optional)

Use a Google Cloud project with Sheets API enabled and a dedicated service account. Share only the attendance spreadsheet with that identity as Viewer. Upload the service-account credential as a Render secret file, set GOOGLE_APPLICATION_CREDENTIALS to its file path, and set DATA_MODE=sheets. The client requests spreadsheets.readonly scope. Do not change the existing Apps Script deployment.

## Operations

The API has a per-process 30-second snapshot cache and five-minute cursor retention. A restart clears it; the app recovers from expired pagination. Logs exclude authorization headers and attendance payloads. Check Render logs for request failure counts without logging raw rows. To roll back, redeploy a previously verified Git commit/image and retain the same environment settings.
