# Implementation verification

Verification date: 2026-09-28. This records executed checks, not merely the planned gates.

## Passed

- Firmware relocation: byte-for-byte comparison against original Git HEAD succeeds. Apps Script writer was not deployed or modified.
- Backend: TypeScript build and 13 domain/API/contract tests pass. Coverage includes sample expected result, date parsing, delayed uploads, duplicates, identity conflicts, repeated/missing scans, midnight pairing, revocation, pagination, invalid filters, expired snapshots and source failures.
- OpenAPI: actual API responses validated against checked-in response schemas.
- Dependencies: npm installation/audit reports zero known vulnerabilities after updating csv-parse to 7.0.3.
- Render Docker image: builds with Node 24; container HTTP smoke test confirms health, denied anonymous access, authenticated sample data, and expected one-minute sample visit. Local Docker requires --network=host because this machine cannot create bridge veth interfaces; this is a local kernel limitation, not a Render setting.
- Live source: the supplied attendance tab was read without modifying it. At verification it contained 13 records, one excluded test row, one member recorded inside and no invalid rows or identity conflicts.
- Flutter: static analyzer reports no issues; four API/widget tests pass.
- Android debug APK built and installed on emulator-5554. Personal-code sign-in succeeded against the local live-sheet API; dashboard and member profile render correctly with live presence, visit totals and anomaly labels.
- Emulator offline check: removing localhost forwarding retained the cached inside count with LAST KNOWN PRESENCE and a connection-error banner.
- Emulator revocation check: setting the local test leader inactive returned the app to sign-in with a revoked-access message and cleared its in-memory attendance view.
- Signed release installed and launched successfully on the emulator with the production server URL field empty.
- Signed Android release APK built successfully (approximately 52 MB). apksigner verifies APK Signature Scheme v2 with one signer.

Release APK SHA-256 at this checkpoint:

`c8a174459e9591ce319872267b31a3d75f309599def19152760b341d589a9408`

## Scope and remaining external checks

The owner will deploy the backend to Render. A Render URL has not been supplied, so actual Render cold-start behavior and the released app's HTTPS connection to that deployment cannot yet be verified. Use docs/render-deployment.md for the handoff. Docker build/runtime verification is local, not evidence of a deployed Render service.

The private Sheets API/service-account adapter is implemented; live integration was verified through the existing public-sheet adapter, not private Google credentials. No sheet sharing settings were changed.

No physical RFID scan was triggered by this work. Live reads reflect existing rows; the original hardware flow is reported working by the owner. The owner disconnected the physical phone and authorized emulator testing.

The release signing key and its password file were generated locally and are ignored by Git. Back up both privately for future APK updates.
