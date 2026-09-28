import { createHash, timingSafeEqual } from "node:crypto";
export type Leader = {
  id: string;
  name: string;
  codeHash: string;
  active: boolean;
};
export const digest = (code: string) =>
  createHash("sha256").update(code).digest("hex");
export function identify(code: string, leaders: Leader[]): Leader | undefined {
  const hash = Buffer.from(digest(code), "hex");
  return leaders.find(
    (l) =>
      l.active &&
      /^[a-f0-9]{64}$/.test(l.codeHash) &&
      timingSafeEqual(hash, Buffer.from(l.codeHash, "hex")),
  );
}
export function parseLeaders(value: string): Leader[] {
  const leaders: unknown = JSON.parse(value);
  if (!Array.isArray(leaders) || !leaders.length)
    throw new Error("LEADERS_JSON must contain approved leaders");
  const ids = new Set<string>();
  for (const leader of leaders) {
    if (
      typeof leader?.id !== "string" ||
      !leader.id ||
      typeof leader.name !== "string" ||
      !leader.name ||
      !/^[a-f0-9]{64}$/.test(leader.codeHash) ||
      typeof leader.active !== "boolean" ||
      ids.has(leader.id)
    )
      throw new Error("Invalid leadership configuration");
    ids.add(leader.id);
  }
  return leaders as Leader[];
}
