# SushiTray

macOS menu bar app for running and controlling a local [sushi](https://github.com/beamivalice/sushi) AI server.

Start and stop `sushi serve` from the tray, watch live prefill/decode tok/s, browse models, launch coding agents, and open the built-in chat UI when the server is ready.

<p align="center">
  <img src="assets/icon.png" alt="SushiTray icon" width="128" />
</p>

## Install

### Homebrew (recommended)

Apple Silicon, macOS 13+:

```bash
brew tap derkan/tap
brew trust derkan/tap          # required once (Homebrew third-party tap policy)
brew install --cask sushitray
```

Upgrade later with:

```bash
brew upgrade --cask sushitray
```

You also need the sushi CLI:

```bash
brew install beamivalice/tap/sushi
```

Then open **SushiTray** from Spotlight / Launchpad (menu bar only — no Dock icon).

> **Gatekeeper:** builds are not notarized yet. If macOS blocks the app:
>
> ```bash
> xattr -cr /Applications/SushiTray.app
> ```

Uninstall:

```bash
brew uninstall --cask sushitray
```

### Build from source

```bash
git clone https://github.com/derkan/SushiTray.git
cd SushiTray
make run-release
```

## Features

- **Start / Stop** the configured `sushi serve` process from the menu bar
- **Tray metrics** — GPU / MEM mini-bars and `P:` / `T:` tok/s parsed from sushi log lines
- **Open chat** — appears under Stop Server when the log reports `chat in your browser: http://…`
- **Models** submenu
  - Server running → OpenAI-compatible `GET /v1/models`
  - Stopped → last cached API list, or disk scan from `--model` / `--model-dir`
- **Agents** submenu — pick a working directory, then open Terminal / iTerm2 / Warp / Ghostty with `sushi launch <agent>` (claude, pi, omp, opencode, codex, hermes, aider)
- **System Stats** — CPU, GPU, memory snapshot
- **Serving Stats** — session prefill/decode and token counts
- **Settings**
  - Editable serve command (UserDefaults)
  - Autostart server (default on)
  - Check for updates automatically (default on) — sushi CLI + SushiTray
  - Preferred terminal for Agents
  - Brew install hint if `sushi` is missing
  - Live log tail
- Injects `--log-file ~/.sushi/logs/sushi.log` and `--parent-pid` when not already set

## Requirements

- macOS 13.0+ (Ventura or later)
- Apple Silicon (arm64)
- [sushi](https://github.com/beamivalice/sushi) on `PATH` (`brew install beamivalice/tap/sushi`)
- To build from source: Xcode 15+ command line tools

## Usage

1. Launch **SushiTray** — it appears in the menu bar (`LSUIElement`, no Dock icon).
2. If Autostart is enabled (default), the server starts with your saved command.
3. Click the tray icon for status, Start/Stop, Models, Agents, stats, Settings, **Check for Updates…**, About, Quit.
4. When the server logs the chat URL, choose **Open chat**.
5. **Agents ▸** → choose a folder (Cancel → home) → agent opens in your preferred terminal with `sushi launch … --url …`.

Automatic update checks (Settings, default on) compare:

- **sushi** — installed `sushi --version` vs latest [beamivalice/sushi](https://github.com/beamivalice/sushi) release  
- **SushiTray** — app version vs latest [GitHub Release](https://github.com/derkan/SushiTray/releases)

If an update is available you can apply it (Homebrew when installed that way, otherwise sushi’s updater / Releases page).

### Default serve command

Editable in Settings:

```text
sushi serve --model ~/.sushi/models/Qwen3.8-Flash-Next-Sushi-2bpw \
  --mtp --kv-quant 8 --mtp-head-kv-quant --ctx-size 128000 \
  --max-tokens 32000 --prefix-cache-disk 20GB --prefix-cache-entries 1 \
  --prefix-cache-mem 1GB --temp 1 --skip-mem-preflight
```

Default listen address is sushi’s default (`127.0.0.1:12345`) unless you add `--host` / `--port`.

### Log metrics

Prefill / decode speeds come from lines like:

```text
  <- 40251+88 tokens streamed [prefill: 129.9 tok/s (...), decode: 71.2 tok/s] [tool_calls]
```

## Build & release (maintainers)

```bash
make icons          # from assets/icon.png (needs ImageMagick `magick`)
make run / run-release
make dist           # → dist/SushiTray-<version>.zip + sha256
```

| Target | Description |
|--------|-------------|
| `make run` / `run-release` | Build, bundle, launch |
| `make dist` | Release zip for GitHub / Homebrew |
| `make icons` | Regenerate icons |
| `make clean` | Remove build products |

Publishing a release:

```bash
# bump CFBundleShortVersionString in SushiTray/Info.plist if needed
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions (`.github/workflows/release.yml`) builds the zip, creates the GitHub Release, and (optional) updates [derkan/homebrew-tap](https://github.com/derkan/homebrew-tap) when the `HOMEBREW_TAP_TOKEN` secret is set (repo scope: `contents:write` on the tap).

Open in Xcode: `make xcode`

## Project layout

```text
SushiTray/
├── Package.swift
├── Makefile
├── packaging/homebrew/sushitray.rb   # cask template
├── assets/icon.png
└── SushiTray/                        # sources + Info.plist + icons
```

## Related

- [sushi](https://github.com/beamivalice/sushi) — local MLX AI server
- Homebrew: `derkan/tap` (this app), `beamivalice/tap/sushi` (CLI)

## License

[Apache License 2.0](LICENSE)
