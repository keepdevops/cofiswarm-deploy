"""Driver: run every KV-cache config and emit a markdown results table."""
import math, sys
import mlx.core as mx
import mlx.nn as nn
from mlx_lm.utils import load
from mlx_lm.models.cache import make_prompt_cache, QuantizedKVCache
from tp_cache import TPCache

MODEL = sys.argv[1]
DATA = sys.argv[2]
CHUNKS = int(sys.argv[3]) if len(sys.argv) > 3 else 30
CTX = 512

model, tok = load(MODEL)
tokens = tok.encode(open(DATA).read())


def ppl(make):
    tn = tt = n = 0
    for s in range(0, len(tokens) - 1, CTX):
        w = tokens[s:s + CTX + 1]
        if len(w) < 2:
            break
        inp = mx.array(w[:-1])[None]
        tgt = mx.array(w[1:])[None]
        c = make()
        lo = model(inp, cache=c).astype(mx.float32)
        nll = nn.losses.cross_entropy(lo, tgt, reduction="sum")
        mx.eval(nll)
        tn += nll.item(); tt += tgt.size; n += 1
        if n >= CHUNKS:
            break
    return math.exp(tn / tt)


L = model.layers
configs = [
    ("f16 (reference)", "f16 / f16", lambda: make_prompt_cache(model)),
    ("mlx-q8 (naive groupwise)", "q8 / q8", lambda: [QuantizedKVCache(64, 8) for _ in L]),
    ("mlx-q4 (naive groupwise)", "q4 / q4", lambda: [QuantizedKVCache(64, 4) for _ in L]),
    ("TurboQuant-8bit", "8b / 8b", lambda: [TPCache("turboquant", 8) for _ in L]),
    ("TurboQuant-4bit", "4b / 4b", lambda: [TPCache("turboquant", 4) for _ in L]),
    ("TurboQuant-2bit", "2b / 2b", lambda: [TPCache("turboquant", 2) for _ in L]),
    ("PolarQuant (key-only)", "polar / f16", lambda: [TPCache("polarquant", 4) for _ in L]),
    ("sim-FP8 e4m3", "fp8 / fp8", lambda: [TPCache("fp8", 8) for _ in L]),
]

rows = []
for name, kv, make in configs:
    p = ppl(make)
    print(f"{name:30s} {p:10.3f}", flush=True)
    rows.append((name, kv, p))

print("\n--- MARKDOWN ---")
print(f"| Cache | K / V | PPL ({CHUNKS} chunks) |")
print("|-------|-------|------:|")
for name, kv, p in rows:
    print(f"| {name} | {kv} | {p:.3f} |")
