# mlx-kvquant — real TurboQuant & PolarQuant KV codecs

Implements the **actual** research algorithms (not the llama.cpp `-ctk/-ctv`
approximations in `../start-tpquant.sh`) against mlx-lm, for quality evaluation
on Apple Silicon.

- **TurboQuant** (arXiv:2504.19874): randomized Hadamard rotation makes every
  coordinate follow a fixed distribution, then a data-oblivious Lloyd-Max scalar
  quantizer encodes each coordinate. MSE variant.
- **PolarQuant** (arXiv:2502.02617): random preconditioning + a recursive polar
  transform (adjacent dims → radius+angle) with cheaply-quantized angles. A
  key-cache method (keys quantized, values kept full precision).

## Files

| File | What |
|------|------|
| `tp_codecs.py` | The codecs (RHT, Lloyd-Max fit, polar transform) in MLX. |
| `tp_cache.py`  | `TPCache`, a drop-in mlx-lm cache that applies a codec. |
| `ppl_mlx.py`   | Perplexity harness for one config. |
| `run_compare.py` | Driver that sweeps all configs → markdown table. |
| `paged_cache.py` | PagedAttention-style block-table cache (16-tok blocks) that composes with the codecs. |
| `run_paged.py` | Validates paged == contiguous PPL + reports fragmentation. |
| `fp8_codec.py` | Simulated FP8 (e4m3fn, per-token scale) KV codec — MLX has no native fp8. |
| `radix_cache.py` | RadixAttention-style prefix cache (token radix tree) + re-anchoring. |
| `run_radix.py` | Prefix-reuse demo: bit-exact vs full recompute, hit-rate, re-anchor. |
| `sliding_cache.py` | Sliding-window cache (mlx-lm RotatingKVCache + codec, default FP8). |
| `preset.py` | Regime → cache-stack presets (`dynamic-short`, `long-context`). |
| `run_preset.py` | dynamic-short validation: PPL vs sliding-window size. |
| `RESULTS.md`   | Latest numbers + interpretation. |
| `RECOMMENDATION.md` | Which combination to use, by regime (start here). |
| `ORCHESTRATION.md` | KV strategies by serving mode / concurrency / persistence. |
| `bench_sglang_radix.py` | SGLang RadixAttention parity+speed bench (run on NVIDIA; untested here). |
| `PARITY.md` | How to compare SGLang RadixAttention to the MLX harness numbers. |

## Usage

```bash
source ~/.venv-mlx/bin/activate
cd mlx-kvquant

# one config
python ppl_mlx.py \
  --model /Users/caribou/distill/distilled-qwen-m3/mlx_q4 \
  --data  /Users/caribou/test-llama/models/wikitext-2-raw/wiki.test.raw \
  --cache turboquant --bits 4 --ctx 512 --chunks 30

# full sweep -> markdown table
python run_compare.py <mlx_model_dir> <wiki.test.raw> [chunks]
```

`--cache` ∈ `f16 | turboquant | polarquant | fp8`. head_dim must be a power of
two (required by the Hadamard rotation).

```bash
# RadixAttention prefix-reuse demo (bit-exact correctness + re-anchoring)
python run_radix.py <mlx_model_dir> <wiki.test.raw> [prefix_len]
```

## Scope / honesty

This is a **fake-quant eval**: codecs encode→dequantize, carrying the real
reconstruction error, so perplexity reflects genuine codec quality. It does
**not** pack bits or use a fused decode kernel — it measures quality, not the
speed/memory wins (those are CUDA/Triton in the reference repos). For clean
near-lossless 4-bit numbers, use a 7B/8B fp16 MLX model; the small
already-4-bit-quantized model in `RESULTS.md` is unusually KV-sensitive.
