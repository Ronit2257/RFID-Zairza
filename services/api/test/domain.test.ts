import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { parse } from "csv-parse/sync";
import { HEADERS, deriveAttendance, parseTimestamp } from "../src/domain.js";
const row = (
  id: string,
  time: string,
  action = "CHECK-IN",
  reg = "001",
  uid = "AA",
) => [id, "2026-09-22", time, reg, "Test Member", "CSE", action, uid];
test("provided source sample yields one outside member and one minute", async () => {
  const data = deriveAttendance(
    parse(await readFile("fixtures/attendance.csv", "utf8")),
  );
  assert.equal(data.members.length, 1);
  assert.equal(data.members[0]?.presence, "outside");
  assert.equal(data.members[0]?.completedMinutes, 1);
  assert.equal(data.quality.testExclusions, 1);
});
test("normalizes UTC offset, midnight/noon, serial date cells; rejects invalid dates", () => {
  assert.equal(
    parseTimestamp("2026-09-22", "12:00 AM"),
    "2026-09-22T00:00:00+05:30",
  );
  assert.equal(
    parseTimestamp("2026-09-22", "12:00 PM"),
    "2026-09-22T12:00:00+05:30",
  );
  assert.equal(parseTimestamp(46287, 0.5), "2026-09-22T12:00:00+05:30");
  assert.equal(parseTimestamp("2026-02-30", "1:00 PM"), null);
  assert.equal(parseTimestamp("2026-09-22", "13:00 PM"), null);
  assert.equal(parseTimestamp("2026-09-22", "23:60"), null);
});
test("sorts delayed uploads chronologically and exact duplicates count only once", () => {
  const data = deriveAttendance([
    HEADERS,
    row("out", "7:32 PM", "CHECK-OUT"),
    row("in", "7:31 PM"),
    row("in", "7:31 PM"),
  ]);
  assert.equal(data.members[0]?.presence, "outside");
  assert.equal(data.members[0]?.completedMinutes, 1);
  assert.equal(data.quality.exactDuplicates, 1);
  assert.equal(data.members[0]?.regNo, "001");
});
test("repeated check-ins do not reset start or inflate confirmed duration", () => {
  const m = deriveAttendance([
    HEADERS,
    row("a", "7:00 PM"),
    row("b", "7:10 PM"),
    row("c", "8:00 PM", "CHECK-OUT"),
  ]).members[0]!;
  assert.equal(m.visitCount, 1);
  assert.equal(m.completedMinutes, 0);
  assert.ok(m.flags.includes("repeated_check_in"));
  assert.equal(m.visits[0]?.checkInAt, "2026-09-22T19:00:00+05:30");
});
test("unmatched checkout, long-open visits and midnight pairing", () => {
  const m = deriveAttendance(
    [HEADERS, row("out", "6:00 PM", "CHECK-OUT"), row("in", "7:00 PM")],
    true,
    Date.parse("2026-09-24T12:00:00Z"),
  ).members[0]!;
  assert.equal(m.presence, "inside");
  assert.ok(m.flags.includes("long_open_visit"));
  assert.ok(m.flags.includes("unmatched_check_out"));
  const out = row("o", "12:01 AM", "CHECK-OUT");
  out[1] = "2026-09-23";
  assert.equal(
    deriveAttendance([HEADERS, row("i", "11:59 PM"), out]).members[0]
      ?.completedMinutes,
    2,
  );
});
test("conflicting IDs are excluded; ambiguous identity does not claim presence", () => {
  const d = deriveAttendance([
    HEADERS,
    row("a", "7:00 PM"),
    row("a", "8:00 PM"),
    row("b", "7:00 PM", "CHECK-IN", "002"),
    row("c", "7:00 PM"),
  ]);
  assert.equal(d.quality.conflictingIds, 1);
  assert.equal(d.quality.identityConflicts, 1);
  assert.ok(d.members.every((m) => m.presence === "unknown"));
});
test("same-minute scan order is deterministic but duration is uncertain", () => {
  const m = deriveAttendance([
    HEADERS,
    row("a", "7:00 PM"),
    row("b", "7:00 PM", "CHECK-OUT"),
  ]).members[0]!;
  assert.equal(m.presence, "outside");
  assert.ok(m.flags.includes("same_time_scans"));
  assert.equal(m.visits[0]?.confirmedDurationMinutes, null);
});
test("validates schema, maps moved headers, skips malformed rows", () => {
  assert.throws(() => deriveAttendance([["Id"]]), /SOURCE_SCHEMA/);
  const cells = row("a", "7:00 PM");
  const data = deriveAttendance([
    HEADERS.toReversed(),
    cells.toReversed(),
    row("b", "invalid").toReversed(),
  ]);
  assert.equal(data.members.length, 1);
  assert.equal(data.quality.invalidRows, 1);
});
