# KV-cache stack — recommendation

Synthesis of every KV method built and measured in this harness. All numbers are
from the **7B fp16** run (`mlx-community/Mistral-7B-Instruct-v0.3`, wikitext-2),
which is the trustworthy reference — see [`RESULTS.md`](RESULTS.md) for full
tables and the 0.5B outlier. Date: 2026-06-17.

## TL;DR

**Paged blocks + TurboQuant-4bit**, add **RadixAttention + re-anchoring** when the
workload has shared prefixes, add a **sliding window** when context is short.
That single stack covers every regime we measured.

## The four axes (not competitors — pick one per axis)

| Axis | Options tried | Winner | Why |
|------|---------------|--------|-----|
| Precision (codec) | f16, q4/q8, TurboQuant 2/4/8b, PolarQuant, FP8 | **TurboQuant-4bit** (+0.18%) or **FP8** (+0.21%) | Both near-lossless; TurboQuant-4bit gets there at 4 bits vs FP8's 8 — half the bytes at equal quality |
| Allocation | contiguous vs paged | **Paged** | 94% less wasted KV, zero quality cost, helps most with many sequences |
| Cross-request reuse | none vs RadixAttention | **Radix — only if prefixes repeat** | Bit-exact reuse, 89% hit-rate when shared context exists; pure overhead when it doesn't |
| History bound | full vs sliding window | **Sliding window for short-context** | Near-lossless when window >= turn length; caps memory |

## Codec ranking (7B fp16, lower is better)

| Codec | PPL | Δ vs f16 | bits | verdict |
|-------|----:|---------:|-----:|---------|
| TurboQuant-8bit | 8.997 | -0.04% | 8 | noise-level; overkill |
| **TurboQuant-4bit** | 9.017 | **+0.18%** | 4 | **best quality-per-byte** |
| sim-FP8 e4m3 | 9.020 | +0.21% | 8 | best production-realistic default |
| mlx-q4 (naive) | 9.054 | +0.59% | 4 | baseline; TurboQuant ~3x cleaner |
| PolarQuant | 9.184 | +2.03% | ~4 | key-only, lost here |
| TurboQuant-2bit | 10.272 | +14.1% | 2 | the floor; only if forced |

## Recommended stacks by regime

**General-purpose default**
Paged + **TurboQuant-4bit**; add **Radix + re-anchor (every 30-50 turns)** if
prefixes repeat. Best quality-per-byte with fragmentation-free memory.

**Long shared context / branching candidates**
Paged + TurboQuant-4bit + **Radix + re-anchor**. Prefix reuse is bit-exact
(max|diff| = 0.00e+00) and pays off; the maximal stack.

**Highly dynamic / short-context chat**
Paged + **FP8** + **sliding window**, **no radix**. Validated near-lossless at
window >= turn length (window=2048: +0.1% when content fits). FP8 over TurboQuant
here: simplicity/robustness matter more than 4-bit when KV is already small. Set
the window >= worst-case turn length. GQA is fine; MLA's edge only shows above
~32K, which this regime never reaches.

**Pure memory-constrained, quality-tolerant**
TurboQuant-2bit (+14%) only if you must — it is the floor.

## Two honest caveats

1. **TurboQuant-4bit vs FP8 is a real fork, not a tie.** TurboQuant wins on bytes
   (4-bit); FP8 wins on production realism — on real NVIDIA hardware FP8 is a
   native tensor-core format with actual speedups, while here it is *simulated*.
   Targeting real GPUs may flip the choice to FP8 despite the byte count. On this
   MLX quality-only harness, TurboQuant-4bit is the compression winner.
2. **PolarQuant (+2.03%) lost** as implemented (key-only, fixed-bit angles). The
   reference repo's k-means angle codebooks would narrow the gap, but as-built it
   is not in the best combo.

## How to apply (this harness)

```python
from preset import dynamic_short, long_context_branching
# short-context chat:
caches = dynamic_short(model, window=2048)        # paged-style + FP8 + window
# long/branching (pair with RadixTree, see run_radix.py):
caches = long_context_branching(model, "turboquant", 4)
```

See [`README.md`](README.md) for the file map and reproduction commands.
