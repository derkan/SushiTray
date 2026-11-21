---
name: sushi-local-ai
description: Choose, install, and tune local Sushi AI models for Apple Silicon using CPU/GPU, unified memory, SSD space, and workload; generate sushi serve commands, apply model-specific optimizations, and configure SushiTray. Use for Sushi server or SushiTray setup and performance troubleshooting.
---

# Sushi Local AI

Help the user run the right Sushi pack on their Mac. Respond in their language. This portable skill needs a terminal and access to upstream documentation, not a particular agent or connector. Python 3 is optional for the read-only probe.

## Workflow

1. **Inspect before choosing.** Run `python3 scripts/inspect_mac.py --model-dir <intended model directory>` relative to this skill, or use the equivalent read-only commands in [hardware.md](references/hardware.md). Record chip, CPU/GPU cores, native architecture, macOS, physical unified memory, current memory pressure/swap, GPU wired limit, and free space on the actual destination volume. Missing or sandbox-blocked data is unknown, not zero. Never infer the user's hardware from this skill's author's machine.
2. **Inspect existing setup.** Locate Sushi and SushiTray; read `sushi --version`, `sushi serve -h`, `sushi list` when available. Check the current serve command without exposing API keys, the selected model's `config.json`, incomplete-download markers, and existing n-gram table. Do not print environment secrets. If Metal is unavailable in an agent sandbox, report the execution limitation; do not conclude the Mac lacks a GPU or repeatedly launch the engine.
3. **Match the workload.** Use stated priorities; otherwise explain a balanced single-user recommendation and ask only for consequential unknowns (images/video, target context, concurrent agents, commercial use of the GLM assistant). Read [models.md](references/models.md) and [hardware.md](references/hardware.md). Give a recommended model and a lower-resource alternative, explaining fit and quality/context tradeoffs. CPU core count alone does not determine fit or token speed.
4. **Check freshness.** References were checked on **2026-10-27**. Recheck the [support list](https://github.com/beamivalice/sushi#model-support-list), [usage](https://github.com/beamivalice/sushi/blob/main/docs/usage.md), selected model card and installed help before installation/tuning. Reconcile changing defaults, flags and unpublished packs. When offline, label recipes provisional and use locally verified flags; do not fabricate current support.
5. **Generate a concrete plan.** Use [commands.md](references/commands.md) and [installation-and-tray.md](references/installation-and-tray.md). Provide exact pack ID, download path, disk requirement including cache/staging, RAM/GPU budget, context, output cap, KV width, speculation choice, and a paste-ready **single `sushi serve` command**. Put installation, download, and any `sudo sysctl` commands in separate terminal blocks. Prefer a real absolute executable and model path, `--flag value` syntax, and localhost.
6. **Check model-specific improvements.** Read the chosen model section in [models.md](references/models.md); for compatible Qwen packs also read [ngram.md](references/ngram.md). Inspect what is already configured before suggesting a download or change. Account for the extra memory of an optional drafter, vision, and RAM prefix cache. Never carry Qwen flags into GLM or DeepSeek indiscriminately.
7. **Apply only requested work.** A recommendation request produces a plan; an installation/configuration request authorizes the relevant work. State large download sizes and privileged memory-limit changes concretely before doing them, following the host's permission mechanism. Preserve existing working configuration. Do not install other agents, enable autostart, replace model tables, or change system limits merely to answer a sizing question.
8. **Verify and report.** If execution is requested, confirm download completion, launch/readiness, `/v1/models`, a short generation, and logs/memory pressure. Stop the newly started test server before handing control to SushiTray. Test the intended context incrementally; startup alone does not establish long-context stability. Report what was actually tested, remaining unknowns, and rollback steps for applied changes. Do not claim benchmark numbers without measuring them.

## Essential constraints

- Current packs require **Apple Silicon and macOS 26.2+**; SushiTray's own macOS 13 minimum does not lower the engine/model requirement.
- Size by total resident weights plus request state, vision/speculation, prefill workspace and cache, leaving room for macOS and active applications. Disk size and active MoE parameter count are not RAM requirements.
- Keep memory preflight enabled. SushiTray's saved/default command may contain `--skip-mem-preflight`; do not perpetuate it as a universal recommendation.
- Do not apply a high GPU wired limit automatically. Upstream warns that **59,000 MB is the ceiling on a 64 GB Mac**; exceeding it can panic the kernel. Published limits are recipes, not a promise of safety under the user's workload.
- Settings executes argv, not a shell. No `sudo`, `&&`, pipes, variable assignments or command substitutions in Serve Command. Expand paths for flags SushiTray does not expand itself.
- Package only this skill's instructions and helper. Do not bundle model weights, n-gram tables, downloaded drafter derivatives, credentials or user logs.
