import { test } from "node:test";
import assert from "node:assert/strict";
import { digest } from "../src/auth.js";
import { createServer } from "../src/server.js";
import { SnapshotStore, type Source } from "../src/source.js";
import { HEADERS } from "../src/domain.js";
const table = [
  HEADERS,
  ...["01", "02", "03"].map((id) => [
    id,
    "2026-09-22",
    "7:00 PM",
    id,
    `Member ${id}`,
    "CSE",
    "CHECK-IN",
    id,
  ]),
];
const headers = { authorization: "Bearer test-secret" };
const leader = {
  id: "owner",
  name: "Owner",
  active: true,
  codeHash: digest("test-secret"),
};
test("auth protects every attendance route, supports revocation, and health stays public", async () => {
  const leaders = [{ ...leader }];
  const app = createServer(
    new SnapshotStore({ mode: "demo", read: async () => table }),
    () => leaders,
  );
  assert.equal((await app.inject("/health")).statusCode, 200);
  assert.equal((await app.inject("/v1/members")).statusCode, 401);
  assert.equal(
    (await app.inject({ url: "/v1/session", headers })).json().data.id,
    "owner",
  );
  leaders[0]!.active = false;
  assert.equal(
    (await app.inject({ url: "/v1/members", headers })).statusCode,
    401,
  );
  await app.close();
});
test("pagination pins snapshot, filters bind cursor, bad queries fail, no card UID exposed", async () => {
  const app = createServer(
    new SnapshotStore({ mode: "demo", read: async () => table }),
    () => [leader],
  );
  const first = (
    await app.inject({ url: "/v1/members?limit=2", headers })
  ).json();
  assert.equal(first.data.length, 2);
  assert.ok(!JSON.stringify(first).includes("uid"));
  assert.equal(first.meta.insideCount, 3);
  const second = (
    await app.inject({
      url: `/v1/members?limit=2&cursor=${first.nextCursor}`,
      headers,
    })
  ).json();
  assert.equal(second.data.length, 1);
  assert.equal(first.meta.snapshotId, second.meta.snapshotId);
  assert.equal(
    (
      await app.inject({
        url: `/v1/members?limit=1&cursor=${first.nextCursor}`,
        headers,
      })
    ).statusCode,
    400,
  );
  for (const query of [
    "limit=0",
    "from=2026-02-30",
    "from=2026-10-01&to=2026-09-01",
    "unknown=true",
  ])
    assert.equal(
      (await app.inject({ url: `/v1/members?${query}`, headers })).statusCode,
      400,
    );
  assert.equal(
    (await app.inject({ url: "/v1/members?cursor=bad", headers })).statusCode,
    400,
  );
  await app.close();
});
test("refresh coalesces, failures retain stale data; cold source failure is 503", async () => {
  let calls = 0,
    fail = false;
  const source: Source = {
    mode: "live",
    read: async () => {
      calls++;
      await new Promise((r) => setTimeout(r, 10));
      if (fail) throw new Error("offline");
      return table;
    },
  };
  const store = new SnapshotStore(source, true, 0);
  await Promise.all([store.get(), store.get(), store.get()]);
  assert.equal(calls, 1);
  fail = true;
  const old = await store.get();
  assert.equal(store.meta(old).stale, true);
  assert.equal(old.members.length, 3);
  const app = createServer(new SnapshotStore(source), () => [leader]);
  assert.equal(
    (await app.inject({ url: "/v1/members", headers })).statusCode,
    503,
  );
  await app.close();
});
test("expired snapshot and profile date filtering are explicit", async () => {
  const store = new SnapshotStore(
    { mode: "demo", read: async () => table },
    true,
    30000,
    1,
  );
  const app = createServer(store, () => [leader]);
  const first = (
    await app.inject({ url: "/v1/members?limit=1", headers })
  ).json();
  await new Promise((r) => setTimeout(r, 5));
  assert.equal(
    (
      await app.inject({
        url: `/v1/members?limit=1&cursor=${first.nextCursor}`,
        headers,
      })
    ).statusCode,
    409,
  );
  const id = first.data[0].memberId;
  assert.equal(
    (
      await app.inject({
        url: `/v1/members/${id}/events?from=2026-09-23`,
        headers,
      })
    ).json().data.length,
    0,
  );
  assert.equal(
    (await app.inject({ url: "/v1/members/missing", headers })).statusCode,
    404,
  );
  await app.close();
});
