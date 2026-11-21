# Model catalog and special recommendations

Checked 2026-10-27 against the [support list](https://github.com/beamivalice/sushi#model-support-list), [usage guide](https://github.com/beamivalice/sushi/blob/main/docs/usage.md), and all six linked model cards. Also inspected the older 2.6/3bpw cards. Requirements below are minimum card versions; individual flags may require newer Sushi. Prefer a current stable release and inspect its help.

## Current published packs

All six require Apple Silicon, macOS 26.2+, and Sushi-specific loading. Do not direct these artifacts into transformers, vLLM, mlx-lm or exllamav3. Download sizes vary: obtain the current file listing or `sushi list` before committing disk. Values below are card estimates; add prefix-cache allowance and download/swap staging.

| Pack / source | Resident tier | Sushi minimum | Approximate disk | Input |
|---|---:|---:|---:|---|
| [Qwen3.8-Flash-Next-Sushi-2bpw](https://huggingface.co/beamster/Qwen3.8-Flash-Next-Sushi-2bpw) | 48 GB; 32 streamed | 1.0.4 | 65 GiB | Text, image, video |
| [Qwen3.8-Flash-Next-Sushi-STQ-2.75bpw](https://huggingface.co/beamster/Qwen3.8-Flash-Next-Sushi-STQ-2.75bpw) | 64 GB | 1.3.0 | 76 GiB | Text, image, video |
| [Qwen3.8-Flash-Next-Sushi-4bpw](https://huggingface.co/beamster/Qwen3.8-Flash-Next-Sushi-4bpw) | 96 GB | 1.0.0 | 159 GiB | Text, image, video |
| [MiMo-V2.6-Flash-Sushi-2.3bpw](https://huggingface.co/beamster/MiMo-V2.6-Flash-Sushi-2.3bpw) | 128 GB | 1.1.0 | 96 GiB | Text, image |
| [GLM-5.3-Flash-Sushi-2bpw](https://huggingface.co/beamster/GLM-5.3-Flash-Sushi-2bpw) | 96 GB | 1.2.0 | 79.4 GiB | Text, image, video |
| [GLM-5.3-Flash-Sushi-2.4bpw](https://huggingface.co/beamster/GLM-5.3-Flash-Sushi-2.4bpw) | 128 GB | 1.2.0 | 91.1 GiB | Text, image, video |

### Qwen

2bpw fits the smallest published resident tier. STQ 2.75 is the current 64 GB recommendation, replacing older recipes pointing at 2.6bpw. STQ's SPEC1 experts mix 2–4-bit rates; its quality measurements use different prompts and bf16 KV, so do not compare them numerically with another card's KV8 KLD as if they were one benchmark.

Qwen packs include vision and MTP. Use bf16 recurrent state (`--qwen-gdn 16`, needs Sushi ≥1.2.3) for 32/48/64 GB recipes; larger recipes retain the f32 default. Read [ngram.md](ngram.md) for optional table changes. STQ ships a 4-bit table, but its card does not explicitly document interchangeability: verify current compatibility before swapping it.

Optional Qwen DFlash2 is described in the [usage guide](https://github.com/beamivalice/sushi/blob/main/docs/usage.md): `incoai/Qwen3.8-Flash-Next-DFlash2`, about 1.2 GB, Apache-2.0, loaded at 8 bits. It requires an explicit `--drafter <absolute directory>`; simply placing it nearby does not enable it. Default draft depths are 2–8. Account for additional memory and benchmark against MTP; do not assume a reported 2.6bpw improvement also holds for STQ. `--no-drafter` keeps Qwen's MTP. Do not download it when already present or when headroom is insufficient.

### MiMo

Three MTP layers are included; MTP, KV8 and thinking are defaults. The bundled `dflash/` and `audio_tokenizer/` are not loaded by Sushi. Audio/video input is unsupported; do not recommend those assets as an optimization. No n-gram swap recommendation appears on this card. MIT model license.

For long agent sessions, `--preserve-thinking off` retains only the newest turn's reasoning, reducing history but causing re-prefill from the first removed thought. `--mtp-head-kv-quant` quantizes head KV; `--prefill-chunk 2048` is the documented widest useful prompt step. Optional `--prefix-cache-mem 1GB` needs extra RAM; prefer disk cache when tight. These tuning details come from the usage guide.

### GLM (both packs)

Use DFlash2, not the included but unused MTP layer. GLM supports KV8 or bf16 KV16, **not KV4**. The 96 GB 2bpw recipe documents auto-context 512K at KV8 or 300K at KV16; actual available memory remains relevant. `--no-drafter` disables the assistant and decodes serially; `--drafter <absolute directory>` selects a separate assistant. Up to four simultaneous decode requests are supported, but their combined memory must be tested.

Both cards include an unmodified `GLM-5.3-Flash-DFlash2/` assistant with **CC BY-NC-ND 4.0**, separate from the base pack's MIT license. Sushi creates `dflash2/` locally on first load. Follow the cards' instruction to keep that derivative local; never distribute it with this skill. For commercial deployments do not assume the MIT label covers the assistant: omit/disable it or obtain appropriate permission. This is a concrete dependency restriction, not a restriction on selling the skill's own instructions. Neither card recommends a Qwen-style table swap.

## Older published Qwen packs

[2.6bpw](https://huggingface.co/beamster/Qwen3.8-Flash-Next-Sushi-2.6bpw): 64 GB tier, Sushi ≥1.0.4, ~74 GiB disk / 43.9 GiB weights. [3bpw](https://huggingface.co/beamster/Qwen3.8-Flash-Next-Sushi-3bpw): 64 GB tier, Sushi ≥1.0.0, ~79 GiB disk / 49.3 GiB weights. Both support image/video and MTP, require macOS 26.2, and explicitly document 4-bit/bf16 n-gram swaps. Preserve a working existing install unless the user wants migration. Do not call them the latest recommended packs or reuse STQ memory numbers for them. The 3bpw card's quality/context tradeoff and 2.6bpw card's smaller footprint are useful when maintaining older installations.

## DeepSeek: availability gate

[DeepSeek-V4.1-Flash-1017-Sushi-STQ-1.75bpw](https://huggingface.co/beamster/DeepSeek-V4.1-Flash-1017-Sushi-STQ-1.75bpw) returned HTTP 401 during this audit; README says coming soon, while usage already has a recipe. **No model card was accessible.** Recheck publication/access and the current card before offering a download; do not interpret 401 as proof that no model exists. Do not request a token just to complete a recommendation.

For an authorized user with access, usage documents a 128 GB streamed recipe: `--ssd-budget-gb 108 --ctx-size 1000000 --max-tokens 128000`, GPU limit 120000. Streaming is mandatory; disk is about 332.1 GB including 189 GiB SSD Engram tables, plus prefix cache. DSpark and vision are defaults; `--no-mtp` disables DSpark, `--no-vision` omits vision. It has no KV cache/GDN/MTP-head settings: `--kv-quant`, `--qwen-gdn`, `--mtp-head-kv-quant`, `--mtp-typical`, `--mtp-tokenv3`, `--mtp-greedy-tail` are refused. Lower-memory plans are unbenchmarked; `--drop-expert` is lossy. Do not transplant Qwen n-gram instructions into its Engram files.
