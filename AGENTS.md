# SushiTray — Agent Guide

macOS menu bar app that runs and controls a local `sushi serve` process.
UI reference: oMLX-style `NSMenu`. Engineering reference: sibling `LLMBrain` project.

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

1. Status (disabled) — running/stopped + port
2. Start / Stop Server
3. Models ▸ — API → cache → `--model`/`--model-dir` disk
4. System Stats ▸ — CPU / GPU / memory
5. Serving Stats ▸ — session prefill/decode from logs
6. Settings… (`⌘,`)
7. About SushiTray
8. Quit (`⌘Q`)

---

## Server lifecycle

- Tokenize serve command; resolve binary; inject `--log-file` (default `~/.sushi/logs/sushi.log`) and `--parent-pid` if missing.
- Spawn via `Process` argv (not shell).
- Stop: SIGTERM then SIGKILL after ~3s.
- Prefill/decode from log lines matching `prefill: … tok/s` / `decode: … tok/s`.

---

## Layout

```
SushiTray/
├── Makefile
├── Package.swift
├── assets/sushi-icon.png
└── SushiTray/
    ├── AppEntry.swift
    ├── AppDelegate.swift
    ├── Config/
    ├── Server/
    ├── Views/
    └── Utilities/
```
