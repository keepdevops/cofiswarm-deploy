"""Validate the dynamic-short preset: PPL vs sliding-window size (FP8 KV)."""
import math, sys
import mlx.core as mx
import mlx.nn as nn
from mlx_lm.utils import load
from mlx_lm.models.cache import make_prompt_cache
from sliding_cache import CodecRotatingCache

MODEL, DATA = sys.argv[1], sys.argv[2]
CHUNKS = int(sys.argv[3]) if len(sys.argv) > 3 else 5
CTX = 512
WINDOWS = [64, 128, 256, 512]

model, tok = load(MODEL)
tokens = tok.encode(open(DATA).read())


def ppl(make):
    tn = tt = n = 0
    for s in range(0, len(tokens) - 1, CTX):
        w = tokens[s:s + CTX + 1]
        if len(w) < 2:
            break
        inp, tgt = mx.array(w[:-1])[None], mx.array(w[1:])[None]
        lo = model(inp, cache=make()).astype(mx.float32)
        nll = nn.losses.cross_entropy(lo, tgt, reduction="sum")
        mx.eval(nll)
        tn += nll.item(); tt += tgt.size; n += 1
        if n >= CHUNKS:
            break
    return math.exp(tn / tt)


L = range(len(model.layers))
print(f"dynamic-short preset: FP8 KV + sliding window, ctx={CTX}, {CHUNKS} chunks\n")
p_f16 = ppl(lambda: make_prompt_cache(model))
print(f"  f16 full-attention reference          PPL = {p_f16:.3f}")
for win in WINDOWS:
    p = ppl(lambda w=win: [CodecRotatingCache(max_size=w, keep=4, method="fp8") for _ in L])
    tag = " (>= ctx: full context kept)" if win >= CTX else ""
    print(f"  FP8 window={win:<4d}                      PPL = {p:.3f}{tag}")
