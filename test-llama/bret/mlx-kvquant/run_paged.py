"""Validate PagedTPCache: same PPL as contiguous TPCache + fragmentation report."""
import math, sys
import mlx.core as mx
import mlx.nn as nn
from mlx_lm.utils import load
from tp_cache import TPCache
from paged_cache import PagedTPCache, BLOCK

MODEL, DATA = sys.argv[1], sys.argv[2]
CHUNKS = int(sys.argv[3]) if len(sys.argv) > 3 else 10
CTX, METHOD, BITS = 500, "turboquant", 4

model, tok = load(MODEL)
tokens = tok.encode(open(DATA).read())


def ppl(make_caches, collect=None):
    tn = tt = n = 0
    for s in range(0, len(tokens) - 1, CTX):
        w = tokens[s:s + CTX + 1]
        if len(w) < 2:
            break
        inp, tgt = mx.array(w[:-1])[None], mx.array(w[1:])[None]
        caches = make_caches()
        lo = model(inp, cache=caches).astype(mx.float32)
        nll = nn.losses.cross_entropy(lo, tgt, reduction="sum")
        mx.eval(nll)
        tn += nll.item(); tt += tgt.size; n += 1
        if collect is not None:
            collect.append(caches[0].frag_stats())
        if n >= CHUNKS:
            break
    return math.exp(tn / tt)


L = model.layers
frags = []
p_contig = ppl(lambda: [TPCache(METHOD, BITS) for _ in L])
p_paged = ppl(lambda: [PagedTPCache(METHOD, BITS) for _ in L], collect=frags)

print(f"\nmethod={METHOD}-{BITS}bit  block={BLOCK}  chunks={CHUNKS}  ctx={CTX}")
print(f"contiguous TPCache  PPL = {p_contig:.4f}")
print(f"paged     TPCache   PPL = {p_paged:.4f}")
print(f"match: {'YES' if abs(p_contig - p_paged) < 1e-3 else 'NO (diff %.2e)' % abs(p_contig-p_paged)}")

f = frags[0]  # per-512-token sequence
print("\nfragmentation for one 512-token sequence (per layer):")
print(f"  tokens used        : {f['tokens_used']}")
print(f"  paged blocks        : {f['paged_blocks']} x {BLOCK} = {f['paged_alloc_tokens']} slots"
      f"  (waste {f['paged_waste']})")
print(f"  contiguous (step256): {f['contig_alloc_tokens']} slots"
      f"  (waste {f['contig_waste']})")
saved = f['contig_alloc_tokens'] - f['paged_alloc_tokens']
print(f"  slots saved by paging: {saved} "
      f"({100*saved/max(f['contig_alloc_tokens'],1):.1f}% less KV allocated)")
