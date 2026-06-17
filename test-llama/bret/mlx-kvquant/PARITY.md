# SGLang RadixAttention ↔ MLX harness parity

How to compare SGLang's production RadixAttention against the MLX harness
(`run_radix.py`) on the **same** scenario, and what is / isn't comparable.

## Why you can't run both here

This repo's machine is Apple Silicon (M3 Max, no NVIDIA GPU). SGLang's
RadixAttention is CUDA/Triton-kernel based and **does not run here**.
`bench_sglang_radix.py` is therefore written for a GPU host and is **untested on
this Mac**. Smoke-run it on the GPU box before trusting its numbers.

## The three axes

| Axis | Comparable? | Verdict |
|------|-------------|---------|
| **Correctness / quality** | Yes, by construction | Both do *exact* KV reuse → lossless. MLX measured **0.00e+00** diff vs full recompute; SGLang is also exact. Nothing to tune — tied. |
| **Hit-rate / tokens saved** | Yes — workload-determined | Determined by the prefix structure, not the kernel. Same scenario → same hit-rate. MLX: **89.3%** (800 reused / 96 computed, 4 candidates × 24-tok suffix, 200-tok prefix). SGLang should match within a few pp. |
| **Throughput / TTFT** | **No — needs the GPU** | The only axis where RadixAttention's *value* lives (fused kernel). MLX gathers blocks (no fused kernel) and deliberately does not measure speed. This is what `bench_sglang_radix.py` adds. |

So the MLX harness already settles two of three axes; the GPU bench only needs to
(a) confirm hit-rate parity and (b) supply the speed delta.

## The shared scenario

Identical on both sides:
- one shared prefix **P** (~200 tokens),
- **K = 4** candidate continuations, each = P + a distinct ~24-token suffix,
- warm P once, then issue the K candidates (so every candidate hits P).

Expected hit-rate (both engines): `K·|P| / (K·|P| + K·|suffix|)` =
`800 / 896` = **89.3%**. `bench_sglang_radix.py` reports SGLang's measured
hit-rate and flags PARITY if it lands within 5pp of the MLX 89.3%.

## Running the SGLang side (GPU host)

```bash
pip install "sglang[all]"        # CUDA GPU required
python bench_sglang_radix.py \
    --model mistralai/Mistral-7B-Instruct-v0.3 \
    --prefix-tokens 200 --candidates 4 --suffix-tokens 24
```

It runs the scenario twice — radix cache ON (default) and OFF
(`disable_radix_cache=True`) — and prints:

```
radix ON  : hit-rate ~89%   wall <fast>
radix OFF : hit-rate   0%    wall <slow>
speedup   : <off/on>x
hit-rate parity vs MLX: PARITY
```

## Reading the result

- **Hit-rate ≈ 89.3%** → parity confirmed: the MLX harness's prefix-reuse
  accounting faithfully predicts SGLang on the same workload.
- **speedup > 1** → the production payoff RadixAttention's fused kernel delivers
  and the MLX bench structurally cannot (it reuses KV correctly but gathers
  blocks instead of running a paged-attention kernel).
- If hit-rate **diverges**, suspect: SGLang block-granularity rounding, an LRU
  eviction under memory pressure, or a `cached_tokens` meta_info field name that
  changed across SGLang versions (the script warns and reads 0 in that case).

## Caveats

- `bench_sglang_radix.py` is **untested on this machine** (no GPU). Treat it as a
  GPU-host runner, not a validated harness.
- Token counts in the scenario are approximate; the script reports the true
  counts from each response's `meta_info`.
- Quality parity is asserted by construction (both reuse exact KV), not measured
  on the SGLang side — if you want to *prove* it there, diff SGLang's logits with
  and without the cache (should be bit-identical, like the MLX 0.00e+00).
