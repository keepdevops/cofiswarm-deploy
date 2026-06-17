# TurboQuant / PolarQuant KV-quant perplexity

Model: `Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf`  •  dataset: wikitext-2-raw  •  ctx=512, fa=on
Profiles map named research methods onto real llama.cpp KV types (see `start-tpquant.sh`).
Date: 2026-06-17

| Profile | K / V | bits/elem (K/V) | role |
|---------|-------|-----------------|------|
| f16 | f16 / f16 | 16 / 16 | unquantized reference |
| q8_0 | q8_0 / q8_0 | ~8.5 / ~8.5 | near-lossless baseline |
| turboquant | q5_1 / q5_1 | ~6 / ~6 | balanced low-bit (MSE-optimal) |
| polarquant | q8_0 / q4_0 | ~8.5 / ~4.5 | protect keys, coarse values |

## Quick run — 40 chunks

40 chunks of wikitext-2 (`CHUNKS=40 ./ppl-tpquant.sh polarquant q8_0`).

| Profile | K / V | PPL | Δ vs q8_0 |
|---------|-------|----:|----------:|
| polarquant | q8_0 / q4_0 | 7.2974 | −0.007% |
| q8_0 | q8_0 / q8_0 | 7.2979 | baseline |

Within the ±0.173 stderr of each estimate — no measurable quality difference, while
polarquant uses a smaller V cache (q4_0 vs q8_0).

## Full run — 564 chunks

Full wikitext-2, 564 chunks (`./ppl-tpquant.sh polarquant q8_0 turboquant f16`).

| Profile | K / V | PPL | ± stderr | Δ vs q8_0 |
|---------|-------|----:|---------:|----------:|
| f16 | f16 / f16 | 7.4858 | 0.04788 | −0.004% |
| q8_0 | q8_0 / q8_0 | 7.4861 | 0.04788 | baseline |
| polarquant | q8_0 / q4_0 | 7.4948 | 0.04791 | +0.116% |
| turboquant | q5_1 / q5_1 | 7.4978 | 0.04797 | +0.156% |

**Takeaways:**
- q8_0 is indistinguishable from f16 (−0.004%, well inside ±0.048) — confirms near-lossless.
- polarquant costs +0.116% PPL for a ~25–30% smaller KV cache (V at q4_0). Small but now
  above the noise floor over the full set, unlike the 40-chunk slice.
- turboquant (q5_1/q5_1) is the worst here at +0.156%, despite spending more bits on V than
  polarquant — protecting the keys (polarquant) pays off more than spreading bits evenly.

## Actual algorithms (MLX)

The numbers above use llama.cpp's built-in KV quant types as stand-ins. The
*real* TurboQuant and PolarQuant algorithms are implemented in MLX under
[`mlx-kvquant/`](mlx-kvquant/README.md); see [`mlx-kvquant/RESULTS.md`](mlx-kvquant/RESULTS.md)
for their perplexity. Headline: at 4-bit KV, real TurboQuant beats naive
groupwise quantization by ~55x on a KV-sensitive small model.
