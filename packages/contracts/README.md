# API v1 contract

[openapi.json](openapi.json) specifies the implemented API. Actual backend responses are validated against its schemas in services/api/test/contract.test.ts. The Flutter HTTP client consumes these JSON envelopes and has tests for authorization errors and cursor pagination; no generated client package is needed in this version.

All /v1 endpoints require a personal leadership code as a Bearer credential. /v1/session verifies it and returns the leader's display name and source mode. /health is process liveness only.

| Route | Response |
|---|---|
| /v1/presence | Recorded-inside summaries, inside/member counts |
| /v1/members | Directory with q/branch filters |
| /v1/members/{memberId} | Profile and all-time visit summary |
| /v1/members/{memberId}/events | Raw scans, newest first |
| /v1/members/{memberId}/visits | Paired visits, newest first |

Lists support limit (1–100, default 50), cursor, and optional snapshot. Event/visit history accepts from/to ISO calendar dates in club time. Visit filters use check-in date; derivation always runs against full history first. Cursors bind to endpoint, filters, page size and snapshot, expire after five minutes, and return 409 when unavailable. The app retries directory pagination once from the current snapshot.

Member IDs are the first 24 hex characters of SHA-256(normalized registration). They are stable across snapshots; they are identifiers, not secrets. Registration and display names remain available to authorized leaders. Directory responses omit raw card UIDs.

Success responses include data, meta, nextCursor. Metadata reports sourceReadAt, servedAt, stale, source mode, timezone and source quality. A successful HTTP request does not mean source data is fresh; inspect stale and sourceReadAt.

Errors include error.code/message/retryable and requestId. 400 = invalid input, 401 = invalid/revoked code, 404 = missing member/route, 409 = expired snapshot, 429 = too many failed attempts, 503 = source unavailable without cache. There are no write endpoints.
