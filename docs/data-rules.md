# Attendance data and derivation rules

## Source schema

Tab: `Zairza Attendance`. Row 1 contains headers; each subsequent row is a scan event.

| Column | Meaning | Normalization |
|---|---|---|
| Id | Event identifier | Required string; deduplication key, never a timestamp |
| Date | Device-local scan date | Strict YYYY-MM-DD |
| Time | Device-local scan time | Parse h:mm AM/PM; optionally h:mm:ss AM/PM and strict 24-hour time |
| Reg No | Member registration | String; preserve leading zeros |
| Name | Display name | Trim; preserve original spelling/script |
| Branch | Branch label | Trim; do not infer membership permissions |
| Action | Recorded direction | Trim/uppercase; CHECK-IN or CHECK-OUT only |
| Card UID | Card identifier | Trim/uppercase; preserve leading zeros |

Interpret event times in Asia/Kolkata, regardless of phone/server timezone; return ISO 8601 timestamps with offset. Sheets may store date/time cells as numeric values; the adapter must explicitly handle serial dates/time fractions or consistently formatted display values, validated against the actual sheet locale. Do not feed ambiguous formatted dates into a generic date parser. Minute-only values have minute precision; displayed duration is approximate.

Keep raw values and source row numbers for diagnosis. Map columns by validated header names rather than silently reading a shifted schema. Missing/duplicate required headers fail the refresh; an empty sheet with valid headers is valid. Invalid rows are excluded from calculations and counted as data-quality issues, never silently converted into attendance.

## Identity and test data

Proposed MVP member key: normalized registration number. This enables multiple cards for one member when registration is consistent. Missing registration or UID excludes a row from member calculations but retains a diagnostic. Resolve display name and branch from the newest nonempty valid values; preserve historical values on events.

A UID mapped to multiple real registration numbers is an identity conflict: flag it and exclude affected records from confident presence until reviewed. Do not automatically merge people by name or transfer historical activity to a new card owner. If card reassignment is normal, implement an explicit assignment registry with effective dates before launch.

The supplied TEST-001 record uses registration TEST but the same UID as the real member. Proposed configurable test filter: Id starts with `TEST-` OR Reg No equals `TEST` (case-insensitive). Apply before identity checks and expose excluded counts. Confirm this convention before production use; never delete source rows.

## Ordering and duplicates

Deduplicate exact repeated IDs across the whole fetched history, even outside the writer's last-50-row fallback. Identical duplicates count once. Different payloads sharing an ID are conflicts: exclude that ID from calculations and flag it for review.

Sort by parsed event timestamp ascending, then original sheet row ascending for same-time records. The row tie-breaker is deterministic but cannot prove true order for delayed same-minute events; flag those as ambiguous where they affect state. Never sort by Id or assume the last sheet row is the latest scan. Rebuild from the source snapshot after every successful refresh so delayed uploads and edits are reflected.

## Presence and visits

- A member's latest valid recorded action determines recorded presence: CHECK-IN = inside, CHECK-OUT = outside. No valid event = unknown.
- Do not toggle inferred presence on every row; use the supplied Action.
- CHECK-IN opens a visit. CHECK-OUT closes an open visit.
- A repeated CHECK-IN while a visit is open flags an anomaly and does not create another visit or reset its start. The subsequent checkout closes that visit, but its duration is uncertain and excluded from confirmed totals.
- CHECK-OUT without an open visit remains in history and establishes outside status; it contributes no visit duration.
- An unclosed check-in stays open, including across midnight. Do not fabricate a checkout or reset everyone at midnight. Flag visits over a proposed configurable 12-hour threshold for review without changing recorded presence.
- Count visits as opened sessions, with complete/incomplete/anomalous counts separately. Sum duration only for complete, unambiguous sessions. Show ongoing elapsed time separately.
- Process the complete chronological history before applying history date filters, so visits crossing the filter boundary remain correctly paired. Assign a visit to its check-in date; raw events filter by their own date.

“Inside now” means last recorded presence, not proof of physical location. Missing scans, device restarts, and offline uploads can affect it. Show anomalies and source freshness in the UI. A fresh read of Sheets does not prove the ESP32 is online; there is no device heartbeat in this schema.

## Expected supplied sample

With the proposed test filter enabled: exclude TEST-001; member 25110431 is Pratik Tathagata Panda, AIML, card 91D41166. The 19:31 check-in and 19:32 check-out on 2026-09-22 form one completed visit of approximately one minute. Recorded presence is outside and inside count is zero. With test filtering disabled, flag the UID/registration conflict instead of silently combining TEST with 25110431.
