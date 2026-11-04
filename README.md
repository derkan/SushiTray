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

- **Live menu card** — model, status, a click-to-copy OpenAI-compatible API base URL, decode/prefill, GPU MHz, a five-minute decode graph, and slim GPU/RAM utilization bars that refresh while the menu is open
- **Start / Stop** the configured `sushi serve` process from the menu bar
- **Model status** — the first tray row shows centered amber `LOADING` with a soft left-to-right light sweep over the loading text, green `READY` before any prefill rate exists, and red `ERROR` for load failures. Active prefill and the last measured prefill rate retain their `P:` display; Reduce Motion disables the loading animation. While loading, the second row shows a centered, static `SUSHITRAY` label instead of an unavailable decode rate. Loading status comes from fresh `/v1/models` responses, polled every second while pending.
- **LED matrix display** — status and speed share two fixed rows of 12 cells measured from narrow Menlo Regular (8.5 pt). Characters use the font’s measured advance over a dim dot grid; model status and the loading-time brand label are centered; known prefill progress lights that grid in the value area. No layout changes between status, speed, and progress.
- **Tray indicators** — **Model status** (loading / ready / error) is centered without an `S:` prefix; `P:` = **prefill** progress or the last prefill speed; `T:` = generated **tokens per second** (decode speed, displayed as `t/s`). The first row switches between model status and `P:` according to model and request activity.
- **Tray metrics** — compact GPU / MEM / CTX mini-bars without a tray logo or status dot (the logo remains in the dropdown header), and prefill/decode metrics from `/metrics.json` (Sushi 1.5+)
- **Context usage** — CTX shows `context_tokens / context_length` for exactly one active prefill/decode session, with used/limit token counts in its tooltip. Cached sessions are excluded. The bar stays empty and dimmed when there are no active sessions, multiple active sessions, or no known limit; its space remains reserved to keep tray width stable.
- **About** — shows both SushiTray and the installed Sushi CLI version, using the binary configured in the serve command.
- **Server pages** — open Dashboard and Chat on the running server
- **Models** submenu
  - Server running → OpenAI-compatible `GET /v1/models`
  - Stopped → last cached API list, or disk scan from `--model` / `--model-dir`
  - Pack revision updates from `meta.pack_update`, with an action to copy the pull command
- **Agents** submenu — pick a working directory, then open Terminal / iTerm2 / Warp / Ghostty with `sushi launch <agent>` (claude, pi, omp, opencode, codex, hermes, aider)
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
- [sushi](https://github.com/beamivalice/sushi) **1.5.0 or newer** on `PATH` (`brew install beamivalice/tap/sushi`)
- To build from source: Xcode 15+ command line tools

## Usage

1. Launch **SushiTray** — it appears in the menu bar (`LSUIElement`, no Dock icon).
2. If Autostart is enabled (default), the server starts with your saved command.
3. Click the tray indicators for status, Start/Stop, Models, Agents, Settings, **Check for Updates…**, About, Quit.
4. Once the metrics endpoint answers, choose **Chat** or **Dashboard**.
5. **Agents ▸** → choose a folder (Cancel → home) → agent opens in your preferred terminal with `sushi launch … --url …`.

Automatic update checks (Settings, default on) compare:

- **sushi** — installed `sushi --version` vs latest [beamivalice/sushi](https://github.com/beamivalice/sushi) release  
- **SushiTray** — app version vs latest [GitHub Release](https://github.com/derkan/SushiTray/releases)

If an update is available you can apply it (Homebrew when installed that way, otherwise sushi’s updater / Releases page).

### Default serve command

Editable in Settings:

```text
sushi serve --model ~/.sushi/models/Qwen3.8-Flash-Next-Sushi-2bpw \
  --mtp --kv-quant 8 --mtp-head-kv-quant --qwen-gdn 16 --ctx-size 131072 \
  --max-tokens 32000 --prefix-cache-disk 20GB --prefix-cache-entries 1 \
  --prefix-cache-mem 1GB --temp 1
```

Example for a 48 GB Mac with Sushi-2bpw; the app requires Sushi ≥ 1.5.0. On 32 GB use `--ssd-budget-gb` streaming; on 64 GB prefer Sushi-2.6bpw with `--ctx-size 250000`. See [sushi usage](https://github.com/beamivalice/sushi/blob/main/docs/usage.md).

Default listen address is sushi’s default (`127.0.0.1:12345`) unless you add `--host` / `--port`.

### Metrics API (Sushi 1.5+)

SushiTray polls authenticated `GET /metrics.json?since=…` once per second, with at most one request in flight. Live decode speed is the token delta of matching request IDs between polls; idle speed is the last finished request's decode rate. Prefill excludes cached prompt tokens. Active prefill is detected from `gauges.requests_prefilling` or `sessions[].phase`; the tray shows a dot-matrix progress bar and the card shows `Prefilling` before a request finishes. When `prefill_tokens_expected` is available, `prefill_tokens_live / prefill_tokens_expected` sets the uncached prompt progress fill (the tray does not reserve space for a percentage label); otherwise `P: prefill..` uses the same soft light sweep as `LOADING` (static with Reduce Motion enabled). The status/rate column has one fixed pixel width across all states, preventing menu bar resizing. Startup shows `LOADING` immediately, without an empty progress track. A progress bar appears only during active prefill with a known target; unknown prefill progress shows shimmering `P: prefill..`. Missing decode speed appears as `T: … t/s`. Prefill tok/s remains a completed-request metric: the card keeps the last speed visible alongside active progress, and the tray progress tooltip includes the last speed. A new prefill or temporary metrics failure does not erase it. GPU utilization, GPU clock and server memory come from the same feed; both the menu card and MEM mini-bar use Sushi’s `memory_mb` process footprint, matching Dashboard. The card shows used / physical memory in GiB.

The launched command's host, port and API key remain fixed for that process. Dashboard (`/`) and Chat (`/chat`) use that address. A failed metrics poll clears live readings and disables server links until the endpoint recovers. Log-based metrics and compatibility with Sushi versions before 1.5 are intentionally unsupported; logs remain available in Settings for diagnostics.

This update follows the HTTP contracts used by [upstream sushibar v1.5.0](https://github.com/beamivalice/sushi/blob/v1.5.0/src/sushibar/sushibar_logic.zig). SushiTray continues to own its configured child process. It does not discover or stop servers launched by sushibar or another application.

## Runtime efficiency

Unchanged metrics do not publish SwiftUI updates, and the dropdown card refreshes only while its menu is open. The LED grid and text are cached as small bitmaps; Core Animation drives loading/prefill effects without a per-frame SwiftUI/Canvas redraw. Model menus/cache are rewritten only when their data changes. Log polling reads at most 64 KiB per tick and bounds unterminated lines.

Run `swift test` for API parsing, model states, metric publication, bounded history/logs, and CLI version discovery.

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
| `make test` | Regression tests |
| `make release VERSION=X.Y.Z` | Test, build, version commit, tag, push and publish via CI |
| `make icons` | Regenerate icons |
| `make clean` | Remove build products |

Publishing a release (Python 3 and Git push access required):

1. Write and commit `release-notes/X.Y.Z.md` with the changes and compatibility requirements.
2. Commit other tracked changes, then run:

```bash
make release VERSION=1.1.0
```

The command validates the version, increments the app build number, runs tests, builds the signed ZIP, commits the version bump, and atomically pushes the branch and annotated tag to `origin`. The default destination branch is `main` (`RELEASE_BRANCH` overrides it). Uncommitted tracked changes are rejected; use a clean worktree if you have unrelated edits.

GitHub Actions (`.github/workflows/release.yml`) tests and builds the tagged commit, then publishes the ZIP with the committed release notes, installation instructions and checksum. If `HOMEBREW_TAP_TOKEN` is configured, it also updates [derkan/homebrew-tap](https://github.com/derkan/homebrew-tap).

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
