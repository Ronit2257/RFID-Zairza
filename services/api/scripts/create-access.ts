import { randomBytes } from "node:crypto";
import { digest } from "../src/auth.js";
const [id, name] = process.argv.slice(2);
if (!id || !name) {
  console.error('Usage: npm run create-access -- leader-id "Leader name"');
  process.exit(1);
}
const code = randomBytes(24).toString("base64url");
console.log(
  JSON.stringify(
    {
      accessCode: code,
      leader: { id, name, codeHash: digest(code), active: true },
    },
    null,
    2,
  ),
);
