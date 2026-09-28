import Fastify from "fastify";
import { createHash, randomUUID } from "node:crypto";
import { z } from "zod";
import { identify, type Leader } from "./auth.js";
import { summary } from "./domain.js";
import { SnapshotStore, type Snapshot } from "./source.js";
const querySchema = z
  .object({
    q: z.string().max(100).optional(),
    branch: z.string().max(100).optional(),
    from: z.iso.date().optional(),
    to: z.iso.date().optional(),
    limit: z.coerce.number().int().min(1).max(100).default(50),
    cursor: z.string().max(2000).optional(),
    snapshot: z.uuid().optional(),
  })
  .strict();
class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
  ) {
    super(message);
  }
}
export function createServer(
  store: SnapshotStore,
  leaders: () => Leader[],
  logger = false,
) {
  const app = Fastify({
    logger: logger
      ? {
          redact: ["req.headers.authorization"],
          serializers: {
            req: (r) => ({ method: r.method, url: r.url?.split("?")[0] }),
          },
        }
      : false,
    bodyLimit: 4096,
    requestTimeout: 20000,
    genReqId: () => randomUUID(),
  });
  const failures = new Map<string, { count: number; until: number }>();
  app.addHook("onRequest", async (req, reply) => {
    reply
      .header("Cache-Control", "no-store")
      .header("X-Content-Type-Options", "nosniff");
    if (req.url.split("?")[0] === "/health") return;
    const now = Date.now();
    for (const [ip, b] of failures) if (b.until < now) failures.delete(ip);
    const attempts = failures.get(req.ip);
    if (attempts && attempts.count >= 10) {
      reply.header("Retry-After", "60");
      throw new ApiError(
        429,
        "RATE_LIMITED",
        "Too many failed attempts. Try again in a minute.",
      );
    }
    const bearer = /^Bearer (\S+)$/.exec(req.headers.authorization ?? "")?.[1];
    const leader = bearer && identify(bearer, leaders());
    if (!leader) {
      if (failures.size > 10000) failures.clear();
      failures.set(req.ip, {
        count: (attempts?.count ?? 0) + 1,
        until: attempts?.until ?? now + 60000,
      });
      throw new ApiError(
        401,
        "UNAUTHORIZED",
        "Access code is invalid or has been revoked.",
      );
    }
    failures.delete(req.ip);
    (req as typeof req & { leader: Leader }).leader = leader;
  });
  app.setErrorHandler((error, req, reply) => {
    const e =
      error instanceof ApiError
        ? error
        : new ApiError(
            503,
            "SOURCE_UNAVAILABLE",
            "Attendance is temporarily unavailable. Please retry.",
          );
    if (!(error instanceof ApiError))
      req.log.error(
        {
          errorType:
            error instanceof Error && error.message === "SOURCE_SCHEMA"
              ? "source_schema"
              : "upstream_error",
        },
        "Request failed",
      );
    reply
      .status(e.status)
      .send({
        error: {
          code: e.code,
          message: e.message,
          retryable: [409, 429, 503].includes(e.status),
        },
        requestId: req.id,
      });
  });
  app.get("/health", () => ({ status: "ok" }));
  app.get("/v1/session", async (req) => {
    const l = (req as typeof req & { leader: Leader }).leader;
    return { data: { id: l.id, name: l.name, mode: store.source.mode } };
  });
  for (const endpoint of [
    "presence",
    "members",
    "members/:memberId",
    "members/:memberId/events",
    "members/:memberId/visits",
  ]) {
    app.get(`/v1/${endpoint}`, async (req) => {
      const parsed = querySchema.safeParse(req.query);
      if (!parsed.success)
        throw new ApiError(
          400,
          "INVALID_QUERY",
          "Check filters, dates and page size.",
        );
      const q = parsed.data;
      if (q.from && q.to && q.from > q.to)
        throw new ApiError(
          400,
          "INVALID_QUERY",
          "Start date must precede end date.",
        );
      const memberId = (req.params as { memberId?: string }).memberId;
      const filterHash = createHash("sha256")
        .update(
          JSON.stringify({
            endpoint,
            memberId,
            q: q.q,
            branch: q.branch,
            from: q.from,
            to: q.to,
            limit: q.limit,
          }),
        )
        .digest("hex");
      let snapshot: Snapshot;
      let offset = 0;
      if (q.cursor) {
        let cursor: { snapshotId: string; offset: number; filter: string };
        try {
          cursor = JSON.parse(Buffer.from(q.cursor, "base64url").toString());
        } catch {
          throw new ApiError(400, "INVALID_CURSOR", "Invalid page cursor.");
        }
        if (
          cursor.filter !== filterHash ||
          !Number.isSafeInteger(cursor.offset) ||
          cursor.offset < 0
        )
          throw new ApiError(
            400,
            "INVALID_CURSOR",
            "Cursor does not match this request.",
          );
        const old = store.byId(cursor.snapshotId);
        if (!old)
          throw new ApiError(
            409,
            "SNAPSHOT_EXPIRED",
            "Refresh to load the latest attendance.",
          );
        snapshot = old;
        offset = cursor.offset;
      } else if (q.snapshot) {
        const old = store.byId(q.snapshot);
        if (!old)
          throw new ApiError(
            409,
            "SNAPSHOT_EXPIRED",
            "Refresh to load the latest attendance.",
          );
        snapshot = old;
      } else snapshot = await store.get();
      const meta = store.meta(snapshot);
      const member = memberId
        ? snapshot.members.find((m) => m.memberId === memberId)
        : undefined;
      if (memberId && !member)
        throw new ApiError(404, "MEMBER_NOT_FOUND", "Member is unavailable.");
      if (endpoint === "members/:memberId")
        return { data: summary(member!), meta, nextCursor: null };
      let items: unknown[];
      if (endpoint.endsWith("/events"))
        items = member!.events
          .filter(
            (e) =>
              (!q.from || e.occurredAt.slice(0, 10) >= q.from) &&
              (!q.to || e.occurredAt.slice(0, 10) <= q.to),
          )
          .toReversed();
      else if (endpoint.endsWith("/visits"))
        items = member!.visits
          .filter(
            (v) =>
              (!q.from || v.checkInAt.slice(0, 10) >= q.from) &&
              (!q.to || v.checkInAt.slice(0, 10) <= q.to),
          )
          .toReversed();
      else
        items = snapshot.members
          .filter(
            (m) =>
              (endpoint !== "presence" || m.presence === "inside") &&
              (!q.branch || m.branch === q.branch) &&
              (!q.q ||
                `${m.name} ${m.regNo}`
                  .toLowerCase()
                  .includes(q.q.toLowerCase())),
          )
          .map(summary);
      const next =
        offset + q.limit < items.length
          ? Buffer.from(
              JSON.stringify({
                snapshotId: snapshot.id,
                offset: offset + q.limit,
                filter: filterHash,
              }),
            ).toString("base64url")
          : null;
      return {
        data: items.slice(offset, offset + q.limit),
        meta: {
          ...meta,
          total: items.length,
          insideCount: snapshot.members.filter((m) => m.presence === "inside")
            .length,
          memberCount: snapshot.members.length,
          branches: [
            ...new Set(snapshot.members.map((m) => m.branch).filter(Boolean)),
          ].sort(),
        },
        nextCursor: next,
      };
    });
  }
  app.setNotFoundHandler(() => {
    throw new ApiError(404, "NOT_FOUND", "Endpoint not found.");
  });
  return app;
}
