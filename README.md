# SushiTray

macOS menu bar app for running and controlling a local [sushi](https://github.com/beamivalice/sushi) AI server.

## Features

- Start / stop `sushi serve` from the menu bar
- Tray metrics: GPU / MEM bars and prefill / decode tok/s (from log lines)
- Models submenu via OpenAI-compatible `GET /v1/models` (cached when stopped; disk fallback)
- System Stats and Serving Stats submenus
- Settings: editable serve command, brew install hint, log tail

## Prerequisites

- macOS 13.0+
- Xcode 15+ command line tools
- Optional: `sushi` on PATH (`brew install beamivalice/tap/sushi`)

## Quick start

```bash
make icons        # from assets/sushi-icon.png
make run          # debug build + launch
make run-release
```

## Makefile

```
make build / build-debug / build-release
make bundle / run / run-release
make icons
make clean / resolve / xcode
```

## Default command

Configured in Settings (stored in UserDefaults). Default includes the local Qwen model path and common sushi flags. If `--log-file` is omitted, SushiTray injects `~/.sushi/logs/sushi.log` and `--parent-pid` before launch.

## License

MIT
