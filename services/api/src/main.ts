import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { digest, parseLeaders } from "./auth.js";
import {
  fixtureSource,
  sheetsSource,
  publicSheetSource,
  SnapshotStore,
} from "./source.js";
import { createServer } from "./server.js";
const mode = process.env.DATA_MODE ?? "demo";
if (!["demo", "sheets", "public-sheet"].includes(mode))
  throw new Error("DATA_MODE must be demo, sheets or public-sheet");
const demo = mode === "demo";
if (!demo && !process.env.SPREADSHEET_ID)
  throw new Error("SPREADSHEET_ID is required");
const source = demo
  ? fixtureSource(
      resolve(process.env.FIXTURE_PATH ?? "fixtures/attendance.csv"),
    )
  : (mode === "public-sheet" ? publicSheetSource : sheetsSource)(
      process.env.SPREADSHEET_ID!,
      process.env.SHEET_TAB ?? "Zairza Attendance",
    );
const leaders = () =>
  process.env.LEADERS_FILE
    ? parseLeaders(readFileSync(process.env.LEADERS_FILE, "utf8"))
    : process.env.LEADERS_JSON
      ? parseLeaders(process.env.LEADERS_JSON)
      : demo
        ? [
            {
              id: "demo",
              name: "Demo leadership",
              codeHash: digest("zairza-demo"),
              active: true,
            },
          ]
        : (() => {
            throw new Error(
              "Leadership credentials are required for live data",
            );
          })();
leaders();
const store = new SnapshotStore(
  source,
  process.env.EXCLUDE_TEST_ROWS !== "false",
);
const app = createServer(store, leaders, true);
await app.listen({
  host: process.env.HOST ?? "0.0.0.0",
  port: Number(process.env.PORT ?? 8080),
});
for (const signal of ["SIGINT", "SIGTERM"])
  process.on(signal, () => {
    void app.close().then(() => process.exit(0));
  });
