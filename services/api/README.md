# Attendance API

Node.js 24 LTS + TypeScript + Fastify. Read-only attendance service, ready for Docker/Render. See [Render setup](../../docs/render-deployment.md).

```sh
npm ci
npm run test
npm run build
npm start
```

## Configuration

| Variable | Default / meaning |
|---|---|
| DATA_MODE | demo; choose public-sheet or sheets for live data |
| PORT | 8080; automatically honors Render's supplied port |
| HOST | 0.0.0.0 |
| FIXTURE_PATH | fixtures/attendance.csv, relative to services/api |
| SPREADSHEET_ID | Required for both live modes |
| SHEET_TAB | Zairza Attendance |
| EXCLUDE_TEST_ROWS | true; false retains test records in calculations |
| LEADERS_JSON | JSON array of id/name/codeHash/active objects; required for live mode unless LEADERS_FILE is used |
| LEADERS_FILE | Optional path to same JSON; reread on every request for local revocation |
| GOOGLE_APPLICATION_CREDENTIALS | Service-account JSON path for private sheets mode |

Node does not load .env automatically. To use one, run `node --env-file=.env dist/main.js`. Keep local credential files out of Git. A template is provided in .env.example.

`public-sheet` reads the existing link-accessible Google CSV export; it does not publish the sheet or alter its permissions. `sheets` uses the Sheets API with read-only scope and Application Default Credentials. Headers are validated in both modes. The private adapter uses raw serial date/time cells; public mode accepts the supplied YYYY-MM-DD and AM/PM formats and rejects ambiguous formats.

## Personal access codes

```sh
npm run create-access -- president "Club President"
```

Deliver the generated accessCode privately and put the leader object into LEADERS_JSON. Random codes have 192 bits of entropy; store only their hashes. Set active=false and restart/redeploy to revoke an environment-configured leader. Local LEADERS_FILE changes apply immediately. Never use short PINs. The bundled zairza-demo code works only when no custom leadership configuration is supplied in demo mode.

All /v1 routes require Authorization: Bearer CODE. /health is liveness only. Responses are no-store. Authentication failures are rate-limited per observed connection IP; behind a proxy that may be shared, so this is a basic abuse guard, not a full edge firewall. No trust is placed in arbitrary forwarded client IP headers.

## Source and behavior

- Domain logic: src/domain.ts. Whole-source deduplication, chronological sorting, conservative visit duration, identity and sequence anomaly flags.
- Snapshot cache: src/source.ts. 30-second per-process cache, refresh coalescing, stale fallback, five-minute cursor retention.
- HTTP: src/server.ts. Profile/list/history, validated filters, authorization and sanitized errors.
- Public contract: ../../packages/contracts/openapi.json; exercised against actual API responses by contract.test.ts.

No durable attendance database. Server cache disappears on restart. A new process with source failure returns 503; the app may display its encrypted last-known cache. /health can remain successful when Sheets is unavailable. Logs omit codes, payloads and search query values.
