# Command construction and verification

Source: [Sushi usage](https://github.com/beamivalice/sushi/blob/main/docs/usage.md), checked 2026-10-27. These are starting recipes, subject to current help, memory pressure and actual GPU limit. Keep memory preflight enabled. `MODEL` below denotes the chosen directory; substitute a quoted **absolute path** in the delivered command, not a literal variable in SushiTray Settings.

## Downloads

On versions supporting it, prefer `sushi pull beamster/<exact pack name>` (short aliases also work). It downloads to `~/.sushi/models/beamster/<pack name>` and resumes missing/short files. `.pull-incomplete` means unfinished; do not serve the pack or mistake `sushi list` tier labels for proven peak-memory fit. It only accepts the beamster organization. Use `sushi list` for downloaded state and current catalog; offline output may omit recommendations.

Alternatively `hf download beamster/<pack name> --local-dir <absolute directory>` uses the exact directory given. Older examples omit the `beamster/` directory segment; never mix these layouts. Install a current Hugging Face CLI if needed using its current official instructions. Do not reinstall one already available. Authentication is unnecessary for ordinary public packs unless the service requests it; never embed a token in generated commands.

Download once, inspect config and all weight shards, and allow for prefix-cache disk space (up to 20GB in these examples). A table replacement also needs temporary space; see [ngram.md](ngram.md).

## Baseline recipe flags

Begin with `sushi serve --model "<absolute MODEL path>" --host 127.0.0.1 --port 12345` (replace the path). Add the matching row, and quote the resolved executable path if it contains spaces.

| Case | Flags to add |
|---|---|
| Qwen 2bpw, 32 GB streamed | `--ssd-budget-gb 18 --ctx-size 66000 --qwen-gdn 16 --mtp --kv-quant 8 --mtp-head-kv-quant --max-tokens 16000 --temp 1` |
| Qwen 2bpw, 48 GB | `--mtp --kv-quant 8 --mtp-head-kv-quant --qwen-gdn 16 --ctx-size 131072 --max-tokens 32000 --temp 1` |
| Qwen STQ 2.75, 64 GB | `--mtp --kv-quant 8 --mtp-head-kv-quant --qwen-gdn 16 --ctx-size 250000 --max-tokens 32000 --temp 1` |
| Qwen STQ 2.75, 64 GB, explicit long-context tradeoff | `--mtp --kv-quant 4 --mtp-head-kv-quant --qwen-gdn 16 --ctx-size 450000 --max-tokens 64000 --temp 1` |
| Qwen 4bpw, 96+ GB | `--mtp --kv-quant 8 --mtp-head-kv-quant --ctx-size 500000 --prefill-chunk 2048 --max-tokens 64000 --temp 1` |
| MiMo 2.3, 128 GB | `--ctx-size 1048576 --kv-quant 8 --mtp --mtp-head-kv-quant` |
| GLM 2bpw, 96 GB | `--kv-quant 8` (upstream auto-context recipe; see below) |
| GLM 2.4bpw, 128 GB | `--kv-quant 8` (upstream auto-context recipe; see below) |

The streamed Qwen row adds a conservative 16k output cap as **this skill's starting choice**, not an upstream measured optimum. Upstream's streaming example includes `--expert-pick-tolerance 0.3`; leave it out by default because it replaces missed experts with cached approximations and changes replies. Offer it only as a clearly lossy SSD-speed option. Streaming normally omits vision; add `--vision` only when requested and after budgeting its resident tower within `--ssd-budget-gb`. KV/request state costs are additional to that budget.

For GLM and MiMo, derive an explicit output cap from the requested task and context; 32000 is a conservative starting cap, not a card recommendation. For predictable GLM sizing, choose an explicit `--ctx-size` using the memory table, e.g. 131072 for an initial test, and validate larger contexts. MiMo's full 1M row is an upstream capacity recipe; shorten it if not needed. Explain every deviation from the upstream row.

For a single conversation append `--prefix-cache-disk 20GB --prefix-cache-entries 1` only if the disk budget allows; choose a smaller supported budget otherwise. Multiple agents may benefit from 4–8 entries with measured extra usage. `--prefix-cache-mem 1GB` is optional and adds to RAM demand; do not copy it onto a tight 32/48 GB setup automatically. Check the installed help for accepted units and defaults.

## Acceptance checks

- Check port availability and whether SushiTray already owns a running server before a manual start; do not kill an unrelated listener.
- Read the launch log for model identity, context, speculation, vision and cache configuration. Confirm readiness before calling the API.
- `curl --fail http://127.0.0.1:12345/v1/models` should return the intended loaded ID. Use the configured host/port and authentication when changed, keeping secrets out of output.
- Send a short `/v1/chat/completions` request using the returned model ID; then test a representative longer prompt. Use installed API documentation if the request shape has changed.
- Observe prefill/decode rates, errors, swap growth and pressure. Compare one parameter at a time with the same prompt/workload; do not extrapolate benchmark tables to an untested chip.
- Handoff to SushiTray only after stopping a manual test server. Save the new command and restart through Settings; verify again because GUI environment/PATH can differ.
