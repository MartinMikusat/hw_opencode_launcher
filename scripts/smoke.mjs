// End-to-end check without Raycast: spawn `opencode serve`, create a
// session, send a prompt, verify SSE events stream back.
// Usage: node scripts/smoke.mjs [directory]   (default: current dir)
import { spawn } from "node:child_process";
import { existsSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { createOpencodeClient } from "@opencode-ai/sdk";

const directory = realpathSync(process.argv[2] ?? process.cwd());

const bin = [
  join(homedir(), ".opencode/bin/opencode"),
  "/opt/homebrew/bin/opencode",
  "/usr/local/bin/opencode",
].find(existsSync);
if (!bin) throw new Error("opencode binary not found");

const port = 4199;
const url = `http://127.0.0.1:${port}`;
const client = createOpencodeClient({ baseUrl: url });

const up = () =>
  client.path
    .get()
    .then((r) => r.data && realpathSync(r.data.directory) === directory)
    .catch(() => false);

if (!(await up())) {
  spawn(bin, ["serve", "--port", String(port), "--hostname", "127.0.0.1"], {
    cwd: directory,
    detached: true,
    stdio: "ignore",
  }).unref();
  for (let i = 0; i < 80 && !(await up()); i++)
    await new Promise((r) => setTimeout(r, 250));
}
if (!(await up())) throw new Error("server did not come up");
console.log("server up at", url);

const session = await client.session.create({ body: { title: "smoke test" } });
const sessionID = session.data.id;
console.log("session", sessionID);

const { stream } = await client.event.subscribe();
const seen = new Set();
const reader = (async () => {
  for await (const event of stream) {
    if (event.properties?.sessionID !== sessionID) continue;
    seen.add(event.type);
    if (event.type === "session.idle") return;
  }
})();

await client.session.promptAsync({
  path: { id: sessionID },
  body: {
    parts: [
      {
        type: "text",
        text: "Use your bash tool to run exactly: echo raycast-ok — then reply DONE",
      },
    ],
  },
});
await Promise.race([reader, new Promise((_, rej) => setTimeout(() => rej(new Error("timeout")), 120_000))]);

const msgs = await client.session.messages({ path: { id: sessionID } });
const parts = msgs.data.flatMap((m) => m.parts);
const reply = parts
  .filter((p) => p.type === "text")
  .map((p) => p.text)
  .join(" ");
const toolParts = parts.filter((p) => p.type === "tool");

console.log("events seen:", [...seen].sort().join(", "));
console.log("tool parts:", toolParts.map((p) => `${p.tool}:${p.state.status}`).join(", ") || "none");
console.log("reply:", reply.slice(0, 200));
if (!seen.has("message.part.updated")) throw new Error("no streaming events received");
if (toolParts.length === 0) throw new Error("no tool calls — agentic loop not exercised");
if (!reply) throw new Error("empty reply");
console.log("PASS");
