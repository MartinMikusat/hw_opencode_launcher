import { spawn } from "node:child_process";
import { existsSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { createOpencodeClient, type OpencodeClient } from "@opencode-ai/sdk";

export function expandHome(path: string): string {
  if (path === "~") return homedir();
  if (path.startsWith("~/")) return join(homedir(), path.slice(2));
  return path;
}

export function findOpencode(): string {
  for (const bin of [
    join(homedir(), ".opencode/bin/opencode"),
    "/opt/homebrew/bin/opencode",
    "/usr/local/bin/opencode",
  ]) {
    if (existsSync(bin)) return bin;
  }
  return "opencode";
}

function hash(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return Math.abs(h);
}

function sameDir(a: string, b: string): boolean {
  try {
    return realpathSync(a) === realpathSync(b);
  } catch {
    return a === b;
  }
}

// One opencode server per project directory. Port is derived from the
// directory hash (4100-4899); on collision we probe the next port. Servers
// are spawned detached so they outlive the Raycast command.
export async function ensureServer(
  directory: string,
  signal?: AbortSignal,
): Promise<{ client: OpencodeClient; url: string }> {
  const base = 4100 + (hash(directory) % 800);
  for (let offset = 0; offset < 8; offset++) {
    const port = base + offset;
    const url = `http://127.0.0.1:${port}`;
    const client = createOpencodeClient({ baseUrl: url });
    const path = await client.path
      .get()
      .then((r) => r.data)
      .catch(() => undefined);
    if (path) {
      if (sameDir(path.directory, directory)) return { client, url };
      continue; // healthy server, different project
    }
    const child = spawn(
      findOpencode(),
      ["serve", "--port", String(port), "--hostname", "127.0.0.1"],
      { cwd: directory, detached: true, stdio: "ignore" },
    );
    child.unref();
    for (let i = 0; i < 80 && !signal?.aborted; i++) {
      await new Promise((r) => setTimeout(r, 250));
      const path = await client.path
        .get()
        .then((r) => r.data)
        .catch(() => undefined);
      if (path && sameDir(path.directory, directory)) return { client, url };
    }
  }
  throw new Error(`Could not start opencode server for ${directory}`);
}
