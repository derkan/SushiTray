# Hardware and fit

Read-only collection: `sw_vers -productVersion`, `uname -m`, `sysctl -n hw.optional.arm64`, `sysctl -n machdep.cpu.brand_string`, `sysctl -n hw.physicalcpu`, `sysctl -n hw.logicalcpu`, `sysctl -n hw.memsize`, `system_profiler SPDisplaysDataType -json`, `sysctl -n iogpu.wired_limit_mb`, `vm_stat`, `sysctl -n vm.swapusage`, `memory_pressure -Q`, and `df -k <destination-volume>`.

The helper returns selected fields only, avoiding hardware serials and environment variables. A Rosetta process can report x86_64 on Apple Silicon: inspect `hw.optional.arm64` and `sysctl.proc_translated` before rejecting it. Prefer native arm64 Sushi. Detect destination free space using its nearest existing ancestor; do not assume the home volume and an external model volume share capacity.

Physical bytes / 2^30 gives the tier called “GB” in upstream Mac recipes. Keep GB (decimal download bytes) and GiB (2^30 bytes) distinct. Free RAM is transient; macOS reclaimable cache means it is not simply the only usable memory. Use pressure, swap trends, active applications, the actual GPU limit and a load test together. SSD throughput matters especially for streamed experts; do not promise a rate from CPU/GPU core counts or run a large SSD benchmark without a request.

## First candidates (not unconditional admission)

| Physical tier | Balanced first candidate | Alternative / qualification |
|---|---|---|
| Intel, non-macOS, or OS below model requirement | No supported current local recipe | Explain missing prerequisite; do not silently switch runtimes |
| Below 32 GiB | No verified recipe in this snapshot | Do not invent an 8/16/24 GB fit |
| 32–47 GiB | Qwen 2bpw, SSD streaming | 32 GB recipe: 18 GiB resident budget, 66,000 context; sufficient SSD required |
| 48–63 GiB | Qwen 2bpw resident, 131,072 context | Stream only if measured resident budget is inadequate |
| 64–95 GiB | Qwen STQ-2.75bpw, 250,000 context, KV8 | Qwen 2bpw for more context/headroom; KV4 optional for STQ long context |
| 96–127 GiB | Qwen 4bpw, 500,000 context | GLM 2bpw if its capabilities and assistant terms fit |
| 128+ GiB | Compare Qwen 4bpw, GLM 2.4bpw, MiMo 2.3bpw | Choose by task, context and measured quality; highest RAM does not mandate largest model |

For intermediate or larger tiers do not extrapolate a privileged sysctl value. Start with measured limits and the smaller applicable recipe. Multiple agents need additional headroom; upstream tables represent one prompt, not concurrent peak load.

## Upstream resident GPU estimates (GiB)

Source: [Sushi README memory table](https://github.com/beamivalice/sushi#memory), checked 2026-10-27. KV8, Qwen/MiMo MTP with quantized head; GLM includes assistant and vision. Qwen values use f32 GDN; bf16 GDN reduces each by roughly 0.2 GiB. Disk prompt cache and n-gram table are excluded.

| Context | Qwen 2 | Qwen STQ 2.75 | Qwen 4 | MiMo 2.3 | GLM 2 | GLM 2.4 |
|---|---:|---:|---:|---:|---:|---:|
| Weights only | 35.2 | 46.4 | 63.9 | 89.7 | 78.3 | 89.8 |
| 128k | 40.3 | 51.4 | 69.0 | 93.7 | 82.6 | 94.1 |
| 256k | 43.2 | 54.3 | 71.9 | 95.8 | 83.8 | 95.2 |
| 512k | 48.2 | 59.4 | 76.9 | 99.9 | 86.0 | 97.5 |
| 1M | 58.4 | 69.5 | 87.1 | 108.2 | 90.5 | 102.0 |

Use these points as estimates, not a precise interpolation formula or guaranteed admission test. Recheck vision and draft modes against the selected recipe. Prefer the smallest context meeting the task; output tokens share the context budget with input/template/reasoning. A 1M architecture limit is not a recommendation for every Mac.

Upstream example `iogpu.wired_limit_mb`: 32 GB → 27000; 48 → 43000; 64 → 59000; 96 → 90000; 128 → 120000. These reset on reboot. Read and retain the old value before a user-authorized change; restore it after stopping the model if rolling back. Do not install a persistence daemon. Leave operational margin beyond the table's fitting threshold; browsers, IDEs and RAM caches also consume unified memory.

If pressure/swap grows, first shorten context or lower concurrency, remove optional RAM cache, use a smaller pack, or choose verified streaming. Consider KV4 only for supported families and with its quality tradeoff. Do not solve failed preflight by disabling it or raising the wired limit beyond a published ceiling.
