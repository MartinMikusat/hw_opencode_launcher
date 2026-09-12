# Implementation plan — native macOS app

**Pivoted 2026-09-12**: not a Raycast extension — a standalone native launcher
(Swift, SwiftUI + AppKit) summoned by a global hotkey. The opencode backend
story is unchanged (`opencode serve` + REST + SSE); only the client layer moves
from TypeScript/Raycast to Swift.

## Locked decisions

| Decision | Choice |
|---|---|
| Host | Standalone .app, LSUIElement agent, menu bar icon, global hotkey |
| Hotkey | Configurable via KeyboardShortcuts package; default ⌥` |
| Tooling | SwiftPM executable + `scripts/build-app.sh` (bundle + ad-hoc sign). No .xcodeproj in git |
| Working dir | Fixed `~` — agent relocates itself per task (picker removed 2026-09-12) |
| Rendering | Text only — streaming text + "working…" indicator; tool bodies hidden |
| Extras in MVP | Model + agent pickers, completion notifications (UNUserNotificationCenter + own URL scheme) |
| Handoff | Ghostty via `opencode attach <url>` |
| Sessions | Resume past sessions on the `~` server |
| Distribution | Personal; ad-hoc sign. (Store polish from Raycast plan N/A) |
| Old scaffold | Deleted |

## Why native is *easier* here

- Notifications while-closed: `UNUserNotificationCenter` needs no helper
  process — the app can post after the panel hides (watcher lives in-app).
- Deep links: own URL scheme (`opencodepad://session/<id>`) in Info.plist.
- No Raycast runtime constraints: real `Process` spawn, normal PATH handling.

## Architecture

```
global hotkey (KeyboardShortcuts) ─▶ NSPanel (borderless, floating, centered)
     │
     ▼
ChatView (SwiftUI: TextField + ScrollView transcript, text-only)
     │
     ▼
OpencodeClient (URLSession; SSE via .bytes.lines)
     │
     ▼
ServerManager ── ensureServer(~) ──▶ opencode serve --port 4100+hash(dir)
                                      (detached, survives app quit)
```

## Files

```
Package.swift                  executable, macOS 14+, KeyboardShortcuts dep
Sources/OpenPad/
  OpenPadApp.swift             @main, AppDelegate, menu bar item, hotkey
  PanelController.swift        floating Spotlight-style NSPanel
  ChatView.swift               transcript + input, model/agent pickers
  ChatModel.swift              messages, SSE handling, permissions
  OpencodeClient.swift         REST + SSE (Codable types for Part/Event)
  ServerManager.swift          ensureServer
scripts/build-app.sh           swift build -c release → .app bundle → codesign -s -
```

## Work order

1. Package + build script + hello panel (hotkey shows/hides) — proves toolchain
2. OpencodeClient + ServerManager — port probe/spawn, prompt, SSE
3. ChatView minimal loop (fixed ~ dir)
4. Model/agent pickers (menus in panel toolbar)
5. Notifications + URL scheme
6. Sessions view
7. Ghostty handoff, polish

## Verification

- `swift build` after each step; `scripts/build-app.sh` produces runnable .app
- Smoke equivalent: run app, hotkey, prompt "run echo ok via bash", see DONE

## Notes for later

- App working name "OpenPad" (bundle `local.openpad`) — rename freely.
- opencode binary resolution: candidates (`~/.opencode/bin`, homebrew) +
  `/bin/zsh -lc 'which opencode'` fallback.
