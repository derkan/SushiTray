# Installation and SushiTray integration

Sources: [Sushi usage](https://github.com/beamivalice/sushi/blob/main/docs/usage.md), [SushiTray README](https://github.com/derkan/SushiTray), and SushiTray sources inspected at commit `0f89e46d23546f9d2c5f89db1055b5a1ed19e56c` (2026-10-27): `Config/AppConfig.swift`, `Views/SettingsView.swift`, `Utilities/{CommandTokenizer,ServeCommandParser,SushiBinary,AgentLauncher}.swift`, `Package.swift`, `Makefile`.

## Install or update only what is missing

Current engine/model workflow: native Apple Silicon M1+, Metal access, macOS 26.2+ for these packs, enough unified memory and SSD, network for downloads. SushiTray alone targets macOS 13+. Homebrew is required only for the Homebrew route; follow its official installer if absent instead of inventing a shell setup.

```sh
brew install beamivalice/tap/sushi
brew tap derkan/tap
brew trust derkan/tap
brew install --cask sushitray
```

The SushiTray README documents `brew trust` once for its tap. Check the installed Homebrew's help/policy if that command is unavailable. Upgrades are `brew upgrade sushi` and `brew upgrade --cask sushitray`; do not reinstall an up-to-date working setup.

Sushi release binaries are an alternative: inspect [releases](https://github.com/beamivalice/sushi/releases) for the correct arm64 archive and current installation instructions. Extract into a chosen directory and use its absolute executable path. Do not assume `./sushi-macos-arm64/sushi` exists when installed by Homebrew.

For SushiTray source builds: Xcode 15+ command-line tools, Swift 5.9+, Git and make, plus macOS/arm64. Verify `xcode-select -p` and `swift --version`. Clone `https://github.com/derkan/SushiTray.git`, then `make bundle-release` to build without opening it, or `make run-release` to build and launch. The bundle is `.build/app/SushiTray.app` (confirm current Makefile); `make dist` creates a release ZIP under `dist/`. ImageMagick is needed only for `make icons`, not ordinary builds.

Prebuilt SushiTray releases are not notarized in the inspected README. If Gatekeeper blocks a trusted download, explain the specific app and provenance before following its documented quarantine workaround (`xattr -cr /Applications/SushiTray.app`). Do not clear quarantine globally or as an unconditional installation step.

## Configure the existing Settings interface

Open SushiTray (menu bar app, no Dock icon), then Settings (`⌘,`). Autostart is on by default, so prepare the correct model/command before relying on the first launch. It may initially try its saved/default 48 GB recipe.

| Control | Behavior / guidance |
|---|---|
| Serve Command | Full command text, not separate model/context widgets. Paste the generated single executable+argv command. |
| Save | Persists command; does not restart the running server. |
| Start / Restart | Saves the draft then starts/restarts. Restart is shown when running. |
| Reset to Default | Replaces the draft with the built-in 48 GB Qwen 2bpw command; it is not hardware auto-detection. Save/apply deliberately. |
| Autostart server | Starts on app launch, default true. Preserve user's preference. |
| Check for updates automatically | Checks Sushi CLI and SushiTray, default true. |
| Terminal for agents | Terminal, iTerm2, Warp, Ghostty; missing apps are labelled. Default usually Terminal. |
| Analyze… | While running with chat URL, gathers command/session logs/serve help, copies a prompt and opens chat after its dialog; user pastes with ⌘V. Review secrets before sharing logs. |
| Log Tail: Follow / Copy / Clear | Follow scrolling; copy displayed logs; Clear clears displayed lines, not the server's log file. |

Default command contains Qwen 2bpw, MTP, KV8, quantized head, bf16 GDN, 131072 context, 32000 output, 20GB disk prefix cache, one entry, **1GB RAM prefix cache** and **`--skip-mem-preflight`**. Describe that accurately, but generate hardware-appropriate settings with preflight enabled and RAM cache only when justified. The local README's 64 GB 2.6bpw advice predates upstream's STQ recommendation; current upstream wins for new installs.

## Process and path semantics

Settings uses `Process` argv, not shell execution. Quotes, backslash escapes and line continuations work; smart dashes are normalized. Prefer separate `--flag value` tokens because SushiTray's own parser does not recognize `--flag=value` for connection/model discovery. Do not include `sudo`, `cd`, environment assignment, redirection, substitutions or multiple commands.

The resolver searches `/opt/homebrew/bin`, `/usr/local/bin` and PATH; custom installs can use an absolute path. Tilde expansion is provided for `--model`, `--model-dir`, `--log-file`; use absolute paths for `--drafter` and other path-valued flags. `$HOME` is not shell-expanded in Serve Command.

SushiTray injects `--log-file ~/.sushi/logs/sushi.log` and `--parent-pid` if missing. Leave these to the app. `--log-file off` prevents the normal log-driven metrics/chat discovery; don't recommend it for a monitored tray setup. `--host`/`--port` configure API discovery (defaults 127.0.0.1:12345); `--api-key`/`--api-key-env` are parsed, but the latter requires the variable in the GUI process environment, not merely a terminal session. Do not expose keys in example commands or reports.

Models uses live `/v1/models`, then cached data or disk discovery. Selecting a different family changes the model argument, not every family-specific tuning flag: regenerate the full command when moving Qwen→GLM/MiMo/DeepSeek. Open chat appears after the log reports its URL. Serving stats come from prefill/decode log lines; system stats are separate.

Agents menu probes `sushi launch` with fallback claude, pi, omp, opencode, codex, hermes, aider. Current upstream also lists grok; use detected support instead of promising a fixed menu. The preferred terminal must be installed; launching a coding agent requires its own prerequisites. Do not install those agents unless requested. Directory-picker cancellation falls back to home in this app.

Configuration lives in UserDefaults domain `com.derkan.sushitray` (`serveCommand`, `autoStartServer`, `checkForUpdates`, `preferredTerminal`, `lastAgentWorkingDirectory`, `cachedModels`). Prefer Settings to direct writes while running; in-memory state can overwrite external edits. Back up any command you replace. No app-code changes are needed to use this skill.
