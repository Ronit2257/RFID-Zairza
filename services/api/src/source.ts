import { readFile } from "node:fs/promises";
import { parse } from "csv-parse/sync";
import { GoogleAuth } from "google-auth-library";
import { deriveAttendance, type Attendance } from "./domain.js";
import { randomUUID } from "node:crypto";
export type Source = {
  mode: "demo" | "live";
  read: () => Promise<unknown[][]>;
};
export function fixtureSource(path: string): Source {
  return {
    mode: "demo",
    read: async () => parse(await readFile(path, "utf8")) as unknown[][],
  };
}
export function sheetsSource(spreadsheetId: string, tab: string): Source {
  const auth = new GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/spreadsheets.readonly"],
  });
  return {
    mode: "live",
    read: async () => {
      const client = await auth.getClient();
      const range = `'${tab.replaceAll("'", "''")}'!A:H`;
      const url = `https://sheets.googleapis.com/v4/spreadsheets/${encodeURIComponent(spreadsheetId)}/values/${encodeURIComponent(range)}`;
      const response = await client.request<{ values?: unknown[][] }>({
        url,
        params: {
          valueRenderOption: "UNFORMATTED_VALUE",
          dateTimeRenderOption: "SERIAL_NUMBER",
        },
        timeout: 15000,
        retryConfig: { retry: 2 },
      });
      return response.data.values ?? [];
    },
  };
}
export type Snapshot = Attendance & { id: string; readAt: number };
export class SnapshotStore {
  current?: Snapshot;
  private pending?: Promise<Snapshot>;
  private attemptedAt = 0;
  private snapshots = new Map<string, Snapshot>();
  public failed = false;
  constructor(
    public source: Source,
    private excludeTests = true,
    private ttl = 30000,
    private retention = 300000,
  ) {}
  async get(): Promise<Snapshot> {
    const now = Date.now();
    if (this.current && now - this.current.readAt < this.ttl)
      return this.current;
    if (this.pending) return this.pending;
    if (this.current && this.failed && now - this.attemptedAt < 10000)
      return this.current;
    this.attemptedAt = now;
    this.pending = (async () => {
      try {
        const attendance = deriveAttendance(
          await this.source.read(),
          this.excludeTests,
        );
        const snapshot = {
          ...attendance,
          id: randomUUID(),
          readAt: Date.now(),
        };
        this.current = snapshot;
        this.snapshots.set(snapshot.id, snapshot);
        this.failed = false;
        for (const [id, old] of this.snapshots)
          if (Date.now() - old.readAt > this.retention)
            this.snapshots.delete(id);
        return snapshot;
      } catch (err) {
        this.failed = true;
        if (this.current) return this.current;
        throw err;
      } finally {
        this.pending = undefined;
      }
    })();
    return this.pending;
  }
  byId(id: string): Snapshot | undefined {
    const s = this.snapshots.get(id);
    return s && Date.now() - s.readAt <= this.retention ? s : undefined;
  }
  meta(s: Snapshot) {
    return {
      snapshotId: s.id,
      sourceReadAt: new Date(s.readAt).toISOString(),
      servedAt: new Date().toISOString(),
      stale: this.failed || Date.now() - s.readAt > 90000,
      timezone: "Asia/Kolkata",
      mode: this.source.mode,
      quality: s.quality,
    };
  }
}

// Optional adapter for a sheet that its owner has ALREADY made link-readable.
// This never changes sharing permissions. Prefer authenticated Sheets API for private data.
export function publicSheetSource(spreadsheetId: string, tab: string): Source {
  if (!/^[A-Za-z0-9_-]+$/.test(spreadsheetId))
    throw new Error("Invalid spreadsheet ID");
  return {
    mode: "live",
    read: async () => {
      const url = new URL(
        `https://docs.google.com/spreadsheets/d/${spreadsheetId}/gviz/tq`,
      );
      url.searchParams.set("tqx", "out:csv");
      url.searchParams.set("sheet", tab);
      const response = await fetch(url, { signal: AbortSignal.timeout(15000) });
      if (!response.ok) throw new Error("SOURCE_UNAVAILABLE");
      const body = await response.text();
      if (body.length > 10000000 || body.trimStart().startsWith("<"))
        throw new Error("SOURCE_SCHEMA");
      return parse(body, { bom: true }) as unknown[][];
    },
  };
}
