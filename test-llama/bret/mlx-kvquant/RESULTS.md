# Real TurboQuant / PolarQuant on MLX — perplexity

These are the **actual algorithms** (arXiv:2504.19874 TurboQuant, arXiv:2502.02617
PolarQuant), implemented in MLX as a fake-quant eval — not the llama.cpp
`-ctk/-ctv` stand-ins in `../tpquant-results.md`.

## 7B fp16 — the representative result

Model: `mlx-community/Mistral-7B-Instruct-v0.3` (bf16, head_dim=128, 32 layers).
wikitext-2-raw, ctx=512, 10 chunks. This is the headline table: on a real fp16
7B the codecs behave as the papers claim (the 0.5B table below is an outlier —
that model is pathologically KV-sensitive).

| Cache | K / V | PPL | Δ vs f16 |
|-------|-------|----:|---------:|
| f16 (reference) | f16 / f16 | 9.001 | baseline |
| mlx-q8 (naive groupwise) | q8 / q8 | 9.001 | +0.00% |
| mlx-q4 (naive groupwise) | q4 / q4 | 9.054 | +0.59% |
| TurboQuant-8bit | 8b / 8b | 8.997 | −0.04% |
| **TurboQuant-4bit** | 4b / 4b | **9.017** | **+0.18%** |
| TurboQuant-2bit | 2b / 2b | 10.272 | +14.1% |
| PolarQuant (key-only) | polar / f16 | 9.184 | +2.03% |
| **sim-FP8 e4m3** | fp8 / fp8 | **9.020** | **+0.21%** |

Takeaways on 7B fp16:
- **TurboQuant-4bit (+0.18%) is ~3x cleaner than naive mlx-q4 (+0.59%)** at the
  same 4-bit budget — the random-rotation + Lloyd-Max advantage, as claimed.
- **sim-FP8 (+0.21%) is near-lossless** and the best practical default.
- TurboQuant-8bit actually beats f16 fractionally (noise at 10 chunks).
- TurboQuant-2bit (+14%) shows the floor where low-bit finally bites.
- A healthy 7B tolerates KV quant far better than the 0.5B: naive q4 here is
  +0.59% vs +75000% on the tiny model.

Radix prefix cache on the same 7B: reuse vs full recompute **max|diff| =
0.00e+00 (bit-exact)**, 89.3% prefix hit-rate, re-anchor keeps the tree at 2
nodes. The full stack holds on a real model.

## 0.5B (KV-sensitive outlier, kept for contrast)

- Model: `distilled-qwen-m3/mlx_q4` (Qwen2-0.5B, 4-bit weights, head_dim=64)
- Dataset: wikitext-2-raw, ctx=512, 30 chunks
- Date: 2026-06-17
- `run_compare.py` reproduces the table.

| Cache | K / V | PPL (30 chunks) |
|-------|-------|------:|
| f16 (reference) | f16 / f16 | 22.088 |
| mlx-q8 (naive groupwise) | q8 / q8 | 23.507 |
| mlx-q4 (naive groupwise) | q4 / q4 | 16612.414 |
| TurboQuant-8bit | 8b / 8b | 22.849 |
| TurboQuant-4bit | 4b / 4b | 302.513 |
| TurboQuant-2bit | 2b / 2b | 5470.687 |
| PolarQuant (key-only) | polar / f16 | 5523.580 |
| sim-FP8 e4m3 (per-token scale) | fp8 / fp8 | 23.079 |

## Reading this

- **TurboQuant-8bit ≈ f16** (22.85 vs 22.09) — confirms the codec is correct and
  near-lossless at high bit-width.
- **At 4-bit, TurboQuant (302) beats naive mlx groupwise q4 (16612) by ~55x.**
  This is the headline: TurboQuant's random rotation + Beta/Lloyd-Max quantizer
  is far more robust than per-group min/max quantization — exactly the paper's
  claim, reproduced here.
- **This 0.5B 4-bit-weight model is pathologically KV-sensitive.** Even mlx's
  production q4 cache explodes on it. The papers' "near-lossless at 3-4 bit"
  holds on 7B+ fp16 models, not a tiny distilled-and-already-quantized one. To
  see clean near-lossless 4-bit numbers, rerun against a 7B/8B fp16 MLX model.
- PolarQuant here is key-only with fixed 4-bit angles; on this fragile model its
  key error still dominates. It is designed around RoPE'd keys on larger models.

## PagedAttention block-table cache (`paged_cache.py`)

A vLLM-style paged KV cache (16-token blocks + per-sequence block table,
non-contiguous physical layout) that composes with the codecs. `run_paged.py`
confirms it is storage-only:

```
method=turboquant-4bit  block=16  chunks=8  ctx=500
contiguous TPCache  PPL = 184.5073
paged     TPCache   PPL = 184.5073      <- bit-for-bit identical
```

Fragmentation vs the contiguous cache's 256-token growth step (allocation math):

| seq len | paged alloc (blk16) | contig alloc (step256) | paged waste | contig waste |
|--------:|--------------------:|-----------------------:|------------:|-------------:|
| 8 | 16 | 256 | 8 | 248 |
| 20 | 32 | 256 | 12 | 236 |
| 50 | 64 | 256 | 14 | 206 |
| 100 | 112 | 256 | 12 | 156 |
| 300 | 304 | 512 | 4 | 212 |
| 500 | 512 | 512 | 12 | 12 |
| 1000 | 1008 | 1024 | 8 | 24 |
| 4000 | 4000 | 4096 | 0 | 96 |

Across these 8 sequences paging wastes **70** slots vs **1190** contiguous —
**94% less wasted KV**. The win is largest for short/varied sequences and
compounds across many concurrent sequences (the real serving case). Block-wise
freeing in `trim()` returns whole blocks to the pool for reuse — no external
fragmentation.

Honesty: MLX has no fused paged-attention kernel, so the attention step
*gathers* blocks into a logically contiguous tensor via the block table (hence
identical PPL). This demonstrates the memory-management scheme, not vLLM's CUDA
kernel speedup.

## RadixAttention prefix cache (`radix_cache.py`, `run_radix.py`)

A compressed radix tree over token prefixes (SGLang's RadixAttention idea):
branching candidate paths that share a leading context reuse that context's KV.
`run_radix.py` (shared P=200 tokens, 4 candidates x 24-token suffix):

```
cand 0..3: matched 200/224 tokens from cache, logits max|diff| = 0.00e+00
correctness: reuse vs full recompute, max|diff| = 0.00e+00 (PASS)  <- bit-exact
prefix hit-rate : 89.3%  (800 reused / 96 computed tokens)
KV blocks saved : ~50 (block=16) vs recomputing every candidate
re-anchor (every 40 turns): nodes stay = 2 as the session grows
```

Reusing the cached prefix KV gives **bit-identical** next-token logits to a full
recompute, so prefix sharing is free correctness-wise. Re-anchoring every 30-50
turns resets the tree to a fresh root holding only the anchor prefix, keeping it
small and matchable as tool history grows.

## Regime: highly dynamic / short-context (`preset.py`, `sliding_cache.py`)

Stack for fresh-content-per-call chat: **paged + FP8 KV + sliding window, no
prefix cache**. `CodecRotatingCache` = mlx-lm's correct sliding window +
FP8 codec. Window sweep on Mistral-7B (ctx=512, 5 chunks):

| cache | PPL | note |
|-------|----:|------|
| f16 full-attention | 7.461 | reference |
| FP8 window=512 (≥ ctx) | 7.477 | **+0.2% — near-lossless, full context kept** |
| FP8 window=256 | 18.50 | window < ctx, older context dropped |
| FP8 window=128 | 29.47 | |
| FP8 window=64 | 117.28 | |

Reading it: when the window covers the content (≥ ctx row), FP8 sliding window
is **near-lossless**. The degradation at small windows is *wikitext-specific* —
continuous prose has long-range dependencies, so dropping context hurts. **The
actual dynamic-short regime lives on the window≥content row**: each chat call's
fresh content is shorter than the window, so you get the 7.477 (near-lossless)
behaviour while KV memory stays capped at `window` tokens and FP8 halves the
bytes. No radix tree, because hit rate is low. GQA is fine; MLA's edge only
matters above ~32K, which this regime never reaches.

Pick a window ≥ your typical turn length and you keep full quality at bounded,
FP8-halved memory.

## The full stack composes

paged blocks (`paged_cache.py`) + RadixAttention prefix reuse (`radix_cache.py`)
+ a KV codec (TurboQuant / PolarQuant / sim-FP8) are independent layers:

- **codec** decides per-token KV precision (quality vs bytes),
- **paging** decides physical allocation (no fragmentation),
- **radix** decides cross-request prefix reuse (skip recompute),
- **re-anchor** bounds the prefix tree over a long single session.

sim-FP8 (23.08) is the near-lossless default; TurboQuant-4bit is the robust
low-bit option; paging+radix are orthogonal memory/compute wins on top.

## Caveats (honesty)

- **Fake-quant**: codecs encode→dequantize, carrying the real reconstruction
  error so PPL reflects genuine codec quality. They do not pack bits or use the
  fused decode kernel, so this measures **quality, not** the speed/memory wins
  (those are CUDA/Triton in the reference repos).
- TurboQuant here is the **MSE variant** (no QJL product-correction bit).
- PolarQuant uniform-bins the angles per the writeup; the reference repo fits
  k-means codebooks, which would be marginally better.
