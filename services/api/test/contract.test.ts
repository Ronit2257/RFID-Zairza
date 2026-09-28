import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import Ajv from "ajv";
import { createServer } from "../src/server.js";
import { SnapshotStore, fixtureSource } from "../src/source.js";
import { digest } from "../src/auth.js";
test("actual responses conform to the checked-in OpenAPI response schemas", async () => {
  const spec = JSON.parse(
    await readFile("../../packages/contracts/openapi.json", "utf8"),
  );
  const ajv = new Ajv({ strict: false });
  ajv.addSchema({ $id: "contract", components: spec.components });
  const app = createServer(
    new SnapshotStore(fixtureSource("fixtures/attendance.csv")),
    () => [
      { id: "test", name: "Test", active: true, codeHash: digest("secret") },
    ],
  );
  const headers = { authorization: "Bearer secret" };
  const members = (await app.inject({ url: "/v1/members", headers })).json();
  const id = members.data[0].memberId;
  for (const [url, schema] of [
    ["/v1/members", "MemberList"],
    ["/v1/presence", "MemberList"],
    [`/v1/members/${id}`, "Profile"],
    [`/v1/members/${id}/events`, "EventList"],
    [`/v1/members/${id}/visits`, "VisitList"],
  ]) {
    const result = (await app.inject({ url, headers })).json();
    const validate = ajv.compile({
      $ref: `contract#/components/schemas/${schema}`,
    });
    assert.ok(validate(result), JSON.stringify(validate.errors));
  }
  const validate = ajv.compile({ $ref: "contract#/components/schemas/Error" });
  assert.ok(validate((await app.inject("/v1/members")).json()));
  await app.close();
});
