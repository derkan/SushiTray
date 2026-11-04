# SushiTray — Agent Guide

macOS menu bar app that runs and controls a local `sushi serve` process.

---

## Engineering norms

- Prefer the simplest implementation that meets current requirements.
- Keep modules focused: AppKit chrome, process lifecycle, discovery, config, SwiftUI settings.
- Do not add speculative abstractions.

---

## Tech stack

| Item | Choice |
|------|--------|
| Language | Swift 5.9+ |
| UI | AppKit status item + NSMenu; SwiftUI Settings window |
| Minimum OS | macOS 13 |
| Build | SPM + Makefile → `SushiTray.app` |
| Config | UserDefaults (`serveCommand`, `cachedModels`) |
| Server binary | `sushi` on PATH or absolute path in command |

---

## Menu

1. Live status card — model, state, click-to-copy `/v1` API URL with inline confirmation, decode/prefill, GPU clock, 5-minute decode graph, GPU/RAM bars
2. Start / Stop Server
3. Models ▸ — API → cache → `--model`/`--model-dir` disk
4. Dashboard / Chat browser links
5. Settings… (`⌘,`)
6. About SushiTray
7. Quit (`⌘Q`)

---

## Server lifecycle

- Tokenize serve command; resolve binary; inject `--log-file` (default `~/.sushi/logs/sushi.log`) and `--parent-pid` if missing.
- Spawn via `Process` argv (not shell).
- Stop: SIGTERM then SIGKILL after ~3s.
- Requires Sushi 1.5.0+: poll authenticated `/metrics.json?since=…` for readiness, live decode deltas, cached-token-adjusted prefill, GPU clock and server memory.
- While loading, center the static `SUSHITRAY` label on the second matrix row.
- Model state comes from fresh `/v1/models` responses for the launched model: centered amber animated `LOADING`, green `READY` before rates exist, red `ERROR` (no `S:` prefix); preserve active and last prefill display. Poll every second while loading. Use two fixed 12-character Menlo Regular 8.5 pt rows, with cell widths measured from the font and a dim dot grid for status/rate/progress so the tray does not resize between states.
- Prefill progress uses `prefill_tokens_live / prefill_tokens_expected` for the uncached prompt tail; known targets light the shared LED matrix cells; unknown targets show shimmering `P: prefill..` text matching model loading, respecting Reduce Motion.
- CTX tray bar uses `context_tokens / context_length` for exactly one active prefill/decode session; ignore cached sessions. Keep its slot reserved and dimmed when unavailable to avoid resizing.
- The menu card and MEM bar use the server’s `memory_mb` footprint against physical RAM, matching Dashboard.
- Publish metrics only when values change; keep graph history non-published and update the dropdown only while visible. Cache LED grid geometry and avoid rewriting unchanged model cache/menu data.
- Logs are for diagnostics only; no legacy log metric fallback. Server links use `/` and `/chat`.
- Manage only the child process launched by SushiTray; do not adopt or signal sushibar-owned servers.

---

## Layout

```
SushiTray/
├── Makefile
├── Package.swift
├── assets/icon.png
└── SushiTray/
    ├── AppEntry.swift
    ├── AppDelegate.swift
    ├── Config/
    ├── Server/
    ├── Views/
    └── Utilities/
```
