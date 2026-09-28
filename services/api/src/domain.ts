import { createHash } from "node:crypto";

export const HEADERS = [
  "Id",
  "Date",
  "Time",
  "Reg No",
  "Name",
  "Branch",
  "Action",
  "Card UID",
];
export type AttendanceEvent = {
  id: string;
  occurredAt: string;
  action: "CHECK-IN" | "CHECK-OUT";
  flags: string[];
  sourceRow: number;
};
export type Visit = {
  id: string;
  checkInAt: string;
  checkOutAt: string | null;
  confirmedDurationMinutes: number | null;
  flags: string[];
};
export type Member = {
  memberId: string;
  regNo: string;
  name: string;
  branch: string;
  presence: "inside" | "outside" | "unknown";
  lastEventAt: string | null;
  flags: string[];
  visitCount: number;
  completedVisits: number;
  completedMinutes: number;
  events: AttendanceEvent[];
  visits: Visit[];
};
export type Quality = {
  invalidRows: number;
  testExclusions: number;
  exactDuplicates: number;
  conflictingIds: number;
  identityConflicts: number;
};
export type Attendance = { members: Member[]; quality: Quality };
const hash = (s: string) =>
  createHash("sha256").update(s).digest("hex").slice(0, 24);
const text = (v: unknown) => String(v ?? "").trim();

export function parseTimestamp(date: unknown, time: unknown): string | null {
  if (
    typeof date === "number" &&
    (!Number.isFinite(date) || date < 0 || date > 2958465)
  )
    return null;
  // Sheets serial dates are local calendar values, not UTC instants.
  const d =
    typeof date === "number" && Number.isFinite(date)
      ? new Date(Date.UTC(1899, 11, 30) + Math.floor(date) * 86400000)
          .toISOString()
          .slice(0, 10)
      : text(date);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) return null;
  let h: number, m: number, s: number;
  if (
    typeof time === "number" &&
    Number.isFinite(time) &&
    time >= 0 &&
    time < 1
  ) {
    const sec = Math.min(86399, Math.round(time * 86400));
    h = Math.floor(sec / 3600);
    m = Math.floor((sec % 3600) / 60);
    s = sec % 60;
  } else {
    const match = /^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)?$/i.exec(
      text(time),
    );
    if (!match) return null;
    h = Number(match[1]);
    m = Number(match[2]);
    s = Number(match[3] ?? 0);
    if (match[4]) {
      if (h < 1 || h > 12) return null;
      h = (h % 12) + (match[4].toUpperCase() === "PM" ? 12 : 0);
    }
    if (h > 23 || m > 59 || s > 59) return null;
  }
  const stamp = `${d}T${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}+05:30`;
  const ms = Date.parse(stamp);
  if (
    !Number.isFinite(ms) ||
    new Date(ms + 19800000).toISOString().slice(0, 10) !== d
  )
    return null;
  return stamp;
}

type Row = {
  id: string;
  regNo: string;
  name: string;
  branch: string;
  uid: string;
  action: "CHECK-IN" | "CHECK-OUT";
  occurredAt: string;
  sourceRow: number;
};
export function deriveAttendance(
  values: unknown[][],
  excludeTests = true,
  now = Date.now(),
): Attendance {
  const header = values[0]?.map(text) ?? [];
  if (HEADERS.some((h) => header.filter((v) => v === h).length !== 1))
    throw new Error("SOURCE_SCHEMA");
  const indexes = HEADERS.map((h) => header.indexOf(h));
  const quality: Quality = {
    invalidRows: 0,
    testExclusions: 0,
    exactDuplicates: 0,
    conflictingIds: 0,
    identityConflicts: 0,
  };
  const unique = new Map<string, Row>();
  const conflicts = new Set<string>();
  for (let i = 1; i < values.length; i++) {
    const cells = values[i]!;
    if (cells.every((v) => text(v) === "")) continue;
    const [id, date, time, reg, name, branch, uidAction, uid] = indexes.map(
      (j) => cells[j],
    );
    const idText = text(id),
      regNo = text(reg).toUpperCase();
    if (
      excludeTests &&
      (idText.toUpperCase().startsWith("TEST-") || regNo === "TEST")
    ) {
      quality.testExclusions++;
      continue;
    }
    const occurredAt = parseTimestamp(date, time),
      action = text(uidAction).toUpperCase();
    if (
      !idText ||
      !regNo ||
      !text(uid) ||
      !occurredAt ||
      !["CHECK-IN", "CHECK-OUT"].includes(action)
    ) {
      quality.invalidRows++;
      continue;
    }
    const row: Row = {
      id: idText,
      regNo,
      name: text(name),
      branch: text(branch),
      uid: text(uid).toUpperCase(),
      action: action as Row["action"],
      occurredAt,
      sourceRow: i + 1,
    };
    const previous = unique.get(idText);
    if (previous) {
      if (
        JSON.stringify({ ...previous, sourceRow: 0 }) ===
        JSON.stringify({ ...row, sourceRow: 0 })
      )
        quality.exactDuplicates++;
      else conflicts.add(idText);
    } else unique.set(idText, row);
  }
  quality.conflictingIds = conflicts.size;
  const rows = [...unique.values()].filter((r) => !conflicts.has(r.id));
  const cards = new Map<string, Set<string>>();
  for (const row of rows) {
    const owners = cards.get(row.uid) ?? new Set<string>();
    owners.add(row.regNo);
    cards.set(row.uid, owners);
  }
  const badCards = new Set(
    [...cards].filter(([, owners]) => owners.size > 1).map(([uid]) => uid),
  );
  quality.identityConflicts = badCards.size;
  const grouped = new Map<string, Row[]>();
  for (const row of rows) {
    const group = grouped.get(row.regNo) ?? [];
    group.push(row);
    grouped.set(row.regNo, group);
  }
  const members: Member[] = [];
  for (const [regNo, group] of grouped) {
    group.sort(
      (a, b) =>
        Date.parse(a.occurredAt) - Date.parse(b.occurredAt) ||
        a.sourceRow - b.sourceRow,
    );
    const member: Member = {
      memberId: hash(regNo),
      regNo,
      name: regNo,
      branch: "",
      presence: "unknown",
      lastEventAt: null,
      flags: [],
      visitCount: 0,
      completedVisits: 0,
      completedMinutes: 0,
      events: [],
      visits: [],
    };
    let open: Visit | null = null;
    const ambiguous = new Set<string>();
    for (let i = 1; i < group.length; i++)
      if (group[i]!.occurredAt === group[i - 1]!.occurredAt)
        ambiguous.add(group[i]!.occurredAt);
    for (const row of group) {
      if (row.name) member.name = row.name;
      if (row.branch) member.branch = row.branch;
      const flags: string[] = [];
      if (badCards.has(row.uid)) flags.push("identity_conflict");
      if (ambiguous.has(row.occurredAt)) flags.push("same_time_scans");
      const event: AttendanceEvent = {
        id: row.id,
        occurredAt: row.occurredAt,
        action: row.action,
        flags,
        sourceRow: row.sourceRow,
      };
      member.events.push(event);
      member.lastEventAt = row.occurredAt;
      if (row.action === "CHECK-IN") {
        if (open) {
          event.flags.push("repeated_check_in");
          open.flags.push("repeated_check_in", ...flags);
        } else {
          open = {
            id: row.id,
            checkInAt: row.occurredAt,
            checkOutAt: null,
            confirmedDurationMinutes: null,
            flags: [...flags],
          };
          member.visits.push(open);
        }
      } else if (open) {
        open.checkOutAt = row.occurredAt;
        open.flags.push(...flags);
        if (!open.flags.length)
          open.confirmedDurationMinutes =
            (Date.parse(row.occurredAt) - Date.parse(open.checkInAt)) / 60000;
        open = null;
      } else event.flags.push("unmatched_check_out");
      member.presence = row.action === "CHECK-IN" ? "inside" : "outside";
    }
    if (open && now - Date.parse(open.checkInAt) > 12 * 3600000)
      open.flags.push("long_open_visit");
    member.flags = [
      ...new Set([
        ...member.events.flatMap((e) => e.flags),
        ...member.visits.flatMap((v) => v.flags),
      ]),
    ];
    if (member.flags.includes("identity_conflict")) {
      member.presence = "unknown";
      for (const visit of member.visits) {
        visit.flags.push("identity_conflict");
        visit.confirmedDurationMinutes = null;
      }
    }
    for (const visit of member.visits) visit.flags = [...new Set(visit.flags)];
    member.visitCount = member.visits.length;
    member.completedVisits = member.visits.filter(
      (v) => v.checkOutAt !== null,
    ).length;
    member.completedMinutes = member.visits.reduce(
      (sum, v) => sum + (v.confirmedDurationMinutes ?? 0),
      0,
    );
    members.push(member);
  }
  members.sort(
    (a, b) =>
      a.name.localeCompare(b.name) || a.memberId.localeCompare(b.memberId),
  );
  return { members, quality };
}
export const summary = ({ events, visits, ...member }: Member) => member;
