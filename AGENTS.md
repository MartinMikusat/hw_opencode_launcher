# OpenPad (was raycast-opencode)

A native macOS launcher — Spotlight-style floating panel on a global hotkey —
that acts as an agentic chat harness for [opencode](https://opencode.ai)
(the CLI coding agent). Scope: small-to-medium tasks — quick edits, questions,
personal flows (e.g. "download this YouTube video to iCloud") — not large
project work. Heavy sessions hand off to `opencode attach` in Ghostty.

**History:** started as a Raycast extension; pivoted to a standalone Swift app
(no Raycast dependency). The backend story is identical either way.

## Commands

- `swift build` — debug build
- `scripts/build-app.sh` — release build → `build/OpenPad.app` (ad-hoc signed)
- `open build/OpenPad.app` — run

## Architecture

SwiftPM executable + bundle script (no .xcodeproj in git). LSUIElement agent:
menu bar icon only, no Dock. Global hotkey via KeyboardShortcuts (default ⌥`,
rebindable in menu → Keyboard Shortcut…).

```
⌥` hotkey ─▶ PanelController (borderless floating NSPanel)
                │  first show → ChatModel.start()
                ▼
     ChatView (SwiftUI) — text-only transcript, message input
                │
                ▼
     OpencodeClient — URLSession REST + SSE /event stream
                │
                ▼
     ServerManager.ensureServer(~) ─▶ `opencode serve` on port
     4100+hash(dir) (detached — survives app quit, sessions persist)
```

Working directory is fixed to `~` — no directory picker; the agent
relocates itself per task (cd/read whatever rules it needs).

- `Sources/OpenPad/OpencodeClient.swift` — REST + SSE. `Part`/`ServerEvent`
  are hand-decoded Codable unions keyed on `type`. Events nest under
  `properties`.
- `Sources/OpenPad/ChatModel.swift` — @MainActor state machine: start →
  connect to home-dir server; send → lazy session create → `promptAsync` →
  SSE updates. Optimistic user bubbles are matched against the server's
  message echo (`pendingLocalIDs`/`hiddenMessageIDs`). Permission requests →
  NSAlert (once/always/reject). Busy→idle while panel hidden →
  `onIdleWhileHidden` → UNUserNotificationCenter.
- `Sources/OpenPad/ChatView.swift` — header (dir, model picker), transcript
  (text + live tool rows), input bar. Esc = abort while busy, hide when idle.
- `Sources/OpenPad/ServerManager.swift` — port probe via `GET /path` (doubles
  as health check; no `/health` in this API version), detached `Process`
  spawn, binary resolution (`~/.opencode/bin`, homebrew, login-shell PATH).
- `Sources/OpenPad/OpenPadApp.swift` — AppDelegate: status item, hotkey,
  settings window (shortcut recorder), notification delegate, URL scheme.

## Feasibility findings (verified against this machine, opencode 1.18.30)

- opencode is client/server by design: the TUI is just a client of its own
  server. The full agent loop — tools, MCPs, plugins, permissions — runs
  server-side; this app is a dumb client exactly like the TUI.
- Verified live: server spawn → session → `promptAsync` → SSE stream
  (`message.part.delta/updated`, `session.idle`) → real `bash` tool call
  completing. MCPs connect automatically (playwright/basic-memory/user-fff
  verified `connected` via `client.mcp.status()`; apple-notes fails —
  pre-existing npx issue unrelated to this app).
- **Permissions:** global config `"permission": "allow"` → nothing prompts.
  If tightened, `permission.updated` events → NSAlert →
  `POST /session/:id/permissions/:pid` (`once`/`always`/`reject`).
- Detached servers persist: fire a long task, quit the app, it finishes anyway.
- Slash commands executable via `POST /session/:id/command` (not wired).
- opencode SDK note: no `/global/health` in SDK 1.18.30 — `GET /path` is the
  probe. Swift client hand-rolls the API (small surface, ~10 endpoints).

## Roadmap / gaps

- Sessions view for resuming past sessions (a persisted server registry was
  removed with the directory picker — re-add alongside this UI; notification
  deep links currently just show the panel).
- `session.command` for slash commands; `@agent` inline syntax.
- Ghostty handoff is wired (`⌘O`) but the `-e` invocation path needs a live
  test on a real desktop session.
- App icon, onboarding (permission grant for notifications), login-item
  launch toggle.
