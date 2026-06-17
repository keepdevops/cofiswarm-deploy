"""Perplexity harness for the real TurboQuant / PolarQuant KV codecs on MLX.

Runs a sliding-window perplexity eval with a chosen KV cache and prints PPL, so
the genuine algorithms can be compared head-to-head with the llama.cpp -ctk/-ctv
approximation numbers in ../tpquant-results.md.

Usage:
  python ppl_mlx.py --model <mlx_model_dir> --data <wiki.test.raw> \
      --cache f16|turboquant|polarquant [--bits 4] [--ctx 512] [--chunks 40]
"""

import argparse
import math
import sys

import mlx.core as mx
import mlx.nn as nn
from mlx_lm.models.cache import make_prompt_cache
from mlx_lm.utils import load

from tp_cache import TPCache


def build_caches(model, cache_kind: str, bits: int):
    if cache_kind == "f16":
        return make_prompt_cache(model)  # default KVCache per layer
    n = len(model.layers)
    return [TPCache(method=cache_kind, q_bits=bits) for _ in range(n)]


def perplexity(model, tokens, cache_kind, bits, ctx, max_chunks):
    """Mean NLL over non-overlapping ctx-sized windows; fresh cache per window."""
    total_nll, total_tok, n_chunks = 0.0, 0, 0
    for start in range(0, len(tokens) - 1, ctx):
        window = tokens[start : start + ctx + 1]
        if len(window) < 2:
            break
        inp = mx.array(window[:-1])[None]
        tgt = mx.array(window[1:])[None]

        cache = build_caches(model, cache_kind, bits)
        logits = model(inp, cache=cache).astype(mx.float32)
        nll = nn.losses.cross_entropy(logits, tgt, reduction="sum")
        mx.eval(nll)

        total_nll += nll.item()
        total_tok += tgt.size
        n_chunks += 1
        print(f"  chunk {n_chunks:3d}  ppl_so_far={math.exp(total_nll/total_tok):.4f}",
              end="\r", flush=True)
        if max_chunks and n_chunks >= max_chunks:
            break
    print()
    if total_tok == 0:
        raise RuntimeError("no tokens evaluated - dataset too short for ctx")
    return math.exp(total_nll / total_tok), n_chunks


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--data", required=True)
    ap.add_argument("--cache", default="f16",
                    choices=["f16", "turboquant", "polarquant", "fp8"])
    ap.add_argument("--bits", type=int, default=4)
    ap.add_argument("--ctx", type=int, default=512)
    ap.add_argument("--chunks", type=int, default=0, help="0 = full dataset")
    args = ap.parse_args()

    try:
        with open(args.data, "r", encoding="utf-8", errors="ignore") as f:
            text = f.read()
    except OSError as e:
        print(f"ERROR: cannot read dataset {args.data}: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Loading model: {args.model}")
    model, tokenizer = load(args.model)
    tokens = tokenizer.encode(text)
    print(f"cache={args.cache} bits={args.bits} ctx={args.ctx} "
          f"tokens={len(tokens)} chunks={args.chunks or 'full'}")

    ppl, n = perplexity(model, tokens, args.cache, args.bits, args.ctx, args.chunks)
    label = args.cache + (f"-{args.bits}bit" if args.cache == "turboquant" else "")
    print(f"\nRESULT  {label:18s}  PPL = {ppl:.4f}  ({n} chunks, ctx={args.ctx})")


if __name__ == "__main__":
    main()
