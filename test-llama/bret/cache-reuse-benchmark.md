# cache-reuse (KV token recycling) benchmark

Model: Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf
Backend: Metal, flash-attn on, unified KV, KV quant q8_0, parallel=1, ctx=8192
Binary: /Users/Shared/llama/llama.cpp/build/bin/llama-server
Date: 2026-06-16

## Setup
Two identical servers, only `--cache-reuse` differs:
- OFF: port 8102, `--cache-reuse 0`
- ON : port 8101, `--cache-reuse 256`

Metric: `/completion` `timings.prompt_ms` for a TEST prompt =
`SYS (shared prefix) + per-round-unique MID (varying length) + long shared BODY (~1800 tok) + TAIL`.
Unique MID each round defeats the exact-prompt cache, so only KV-shifting could
reuse the shifted BODY.

## Result A — isolated (novel prompts, shifted body)
| round | OFF reuse=0 (ms) | ON reuse=256 (ms) |
|------:|-----------------:|------------------:|
| 0 (warmup) | 5453.1 | 5456.4 |
| 1 | 5448.4 | 5455.6 |
| 2 | 5450.3 | 5451.8 |
| 3 | 5457.9 | 5458.8 |
| 4 | 5454.8 | 5458.4 |
| **median (warm)** | **5452.6** | **5457.0** |

**Speedup from --cache-reuse: 1.00x (none).**
Server log on ON shows only `graphs reused` (compute-graph cache), no KV token
reuse — the shifted BODY was fully recomputed. Conclusion: on this Metal/
flash-attn build, --cache-reuse did not accelerate the shifted-body workload.

## Result B — what actually speeds things up: multi-prompt prompt cache
When the SAME prompt repeats, llama-server matched it from its multi-prompt
cache (`cache state: 4 prompts`), evaluating 1 token instead of 2911:
- cold (first compute): ~5450 ms (2911 tokens)
- warm (exact repeat) : ~23 ms (1 token)
- **~237x faster / 99.6% fewer tokens recomputed** — on by default, independent
  of --cache-reuse.

## Takeaway
- `--cache-reuse` gave no win here; keep it (harmless) but don't expect speedup
  on Metal for shifted prefixes.
- Real latency win comes from prompt caching exact/longest-prefix repeats.

## Servers left running (per request)
- 8095 : production server (start-kvquant.sh, parallel=4)
- 8101 : benchmark ON  (cache-reuse 256)
- 8102 : benchmark OFF (cache-reuse 0)
