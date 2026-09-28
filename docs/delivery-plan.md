# Flutter delivery plan

> Historical planning record. Implementation now uses Flutter, a Render-ready API, and personal leadership access codes. Firebase/Cloud Run proposals below are superseded. See [current setup](setup.md) and [verification](verification.md).
Planning only. Flutter is confirmed; no SDK installation or application implementation has started.

## Decisions to settle

- Target: propose Android first, distributed as a signed APK for club testing. Keep Flutter code portable; iOS build/signing will need macOS/Xcode later.
- Audience: choose whether individual histories are administrator-only, visible to all approved members, or self-only with administrator access. All options still support an inside-now screen, with visible fields governed by that policy.
- Hosting: recommend Cloud Run when billing is acceptable; Render Free is the prototype fallback for a strict no-billing constraint.
- Login: propose Google sign-in through Firebase Auth. Attendance registration numbers identify members, while verified login accounts identify viewers; linking them requires administrator verification for self-only access.
- Data: confirm the TEST filter, existing card reassignment/multiple-card usage, and whether long-open sessions should simply display a warning. Preserve all raw rows.

These pending choices do not prevent local fixture development once implementation is requested. They must be resolved before enabling live user access. No unanswered question is treated as approval for cloud spending or deployment.

## Step-by-step work and exit conditions

| Phase | Work | Done when |
|---|---|---|
| 1. Environment | Install Flutter and missing Android SDK; configure editor; pin compatible versions | flutter doctor validates Android tooling and flutter devices detects a phone/emulator |
| 2. Product flow | Sketch sign-in, inside-now, members, profile/history and settings screens; settle visible fields and access rules | Every screen has loading, empty, error and stale examples |
| 3. Contract and rules | Author OpenAPI spec and fixtures; implement TypeScript parsing, ordering, identity, presence and sessions | Edge-case tests pass, sample produces one outside member and one completed minute |
| 4. Local API | Add fixture/Sheets source interfaces, endpoints, auth middleware, cache and pagination | Fixture API passes contract and authorization tests without accessing production |
| 5. Flutter app | Create project; models, repositories, view models and Material UI; wire screens to fixture API | Full dashboard → member → history journey runs on physical Android |
| 6. Identity and staging | Configure Firebase Google login and server allowlist; private test sheet and staging hosting | Approved user succeeds; unknown user and expired token cannot read attendance |
| 7. Live data | Configure production Viewer access; inspect formats and validate known scans without writing source rows | Live check-in/out appears after expected refresh and historical ordering matches sheet |
| 8. Reliability and release | Test offline/reconnect, cold starts, account switches, anomalies, accessibility; sign release | Installable APK, reproducible build instructions, deployment rollback and observed checks recorded |

Phases 3–5 can use fixtures while external configuration is prepared. Avoid a decorative UI-only completion: release requires authenticated live data and a device-tested build.

## Mobile behavior

- Bottom navigation: Inside now, Members, Settings. Open a member profile from either list; include history and summary within the profile flow.
- Use recorded action for presence, not number of scans. Derive presence from the complete normalized source before filtering lists/history.
- Poll only while foregrounded every 30 seconds, refresh immediately when returning to the app, and support pull-to-refresh. Avoid overlapping calls.
- Show last successful Sheets read time and a stale banner after 90 seconds. An API response from an old snapshot must not update that timestamp.
- Save the last successful response by account for offline display. Never label offline data as current; clear all attendance cache on logout/account change.
- Display club-local dates/times consistently. Show approximate completed durations separately from open visits and uncertain visits.

## Testing before handoff

Backend: parser and reducer unit tests, OpenAPI response validation, auth/authorization tests, source-failure/recovery tests, same-snapshot pagination and cursor expiry. Use test sheets for mutation scenarios.

Flutter: model/repository/view-model tests, widget tests for meaningful states and permissions, flutter analyze, flutter test, and physical-device integration checks. Validate signed release configuration separately from debug; Google login signing fingerprints can differ.

End to end: scan a known card, observe its uploaded row, verify inside state on refresh, scan out and verify history. Include disconnected phone/reconnection and an already-delayed upload. Hardware source remains unchanged.

## Inputs required at their respective phases

- Environment: physical Android phone or decision to allocate emulator storage.
- UI/access: app display name/club branding and visibility choice; text/initials work until branding is supplied.
- Integration: spreadsheet link/ID, current row volume and growth estimate, source timezone/locale, Viewer sharing capability, test sheet.
- Auth: approved login accounts, owner-verified registration mappings if needed, Android application ID and signing fingerprints.
- Hosting: cloud/project ownership and billing preference; deployment should follow review of a runnable tested build.

Source-of-truth documents: [attendance rules](data-rules.md), [API contract](../packages/contracts/README.md), [hosting proposal](hosting.md), [environment check](flutter-environment.md).
