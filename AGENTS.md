# raycast-opencode

A Raycast extension that acts as an agentic chat harness for [opencode](https://opencode.ai)
(the CLI coding agent). Scope: small-to-medium tasks — quick edits, questions, fixes —
not large project work. Heavy sessions are meant to be handed off to the terminal TUI.

## Commands

- `npm run dev` — `ray develop`, installs the extension into Raycast in dev mode
- `npm run build` — `ray build`
- `npx tsc --noEmit` — typecheck
- `node scripts/smoke.mjs [dir]` — end-to-end check without Raycast: spawns
  `opencode serve`, creates a session, sends a prompt, verifies SSE events stream

## Architecture

Raycast extensions are React (Node.js runtime). opencode exposes a headless HTTP
server (`opencode serve`) with an OpenAPI API and an SSE event stream; the official
`@opencode-ai/sdk` wraps both.

```
Raycast command ──ensureServer()──▶ opencode serve --port <4100+hash(dir)> (detached, per project dir)
                     │
                     ├─ session.create / session.promptAsync  (204, no wait)
                     └─ event.subscribe() ─▶ SSE stream ─▶ message.part.updated → markdown
                                                          session.idle → done
                                                          permission.updated → confirmAlert → respond
```

- **`src/lib/opencode.ts`** — `ensureServer(directory)`: probe the port derived
  from the directory hash (4100–4899); if a server for a different project holds
  it, probe the next port; if none, spawn detached and poll `client.path.get()`
  until up. Servers persist after the command closes, so sessions keep running.
- **`src/chat.tsx`** — `ChatView`: `List` with `filtering={false}`; the search
  bar is the input, each message is a `List.Item` with `List.Item.Detail`
  markdown (parts: text/reasoning/tool/file). Send = Enter; Stop = ⌘.; New Chat
  = ⌘N; handoff to `opencode attach <url>` in Terminal.app = ⌘O.
- **`src/sessions.tsx`** — lists `session.list()` for the configured directory;
  Enter opens `ChatView` with that session id.
- **Preferences** — `defaultDirectory` (required): the project opencode works in.
  One server per directory; switching dirs = separate server + port.

## Feasibility findings (why this works)

- opencode is client/server by design: the TUI is just a client of its own
  server. `opencode serve` + `opencode attach <url>` make external clients
  first-class.
- Everything needed exists in the API: async prompts (`prompt_async`), streaming
  (`/event` SSE: `message.part.delta/updated`, `session.status/idle`), abort,
  permission replies (`POST /session/:id/permissions/:permissionID`), session
  list/diff/todos.
- Verified live on opencode 1.18.30 via `scripts/smoke.mjs`.
- Prior art: `dpshade/raycast-opencode` (GH, ~8★) implements a similar flow —
  worth mining for ideas (session search via FlexSearch, `@path` autocomplete,
  multi-terminal handoff beyond Terminal.app, model/agent pickers).

## Known limitations / next steps

- Single `defaultDirectory` preference — no per-chat directory switching yet
  (`@~/path` in input or a picker would fix this; server-per-dir already works).
- No model/agent picker; prompts use the server defaults (`promptAsync` accepts
  `model`, `agent`, `tools` overrides; `config.providers()` lists options).
- Permission prompt = `confirmAlert` (once/reject); `always` and richer
  metadata rendering not wired.
- Terminal handoff hardcodes Terminal.app via osascript; other terminals
  (Ghostty/iTerm/Warp) need their own branches.
- Parts rendered minimally; `step-finish` (cost/tokens), `patch`, `file` diffs
  could be surfaced better.
