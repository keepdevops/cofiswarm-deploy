"""Demo: RadixAttention prefix reuse across branching candidates on the model.

Shared context P is computed once; K candidate continuations C+s_i reuse P's KV
from the radix tree and only compute their own suffix. We verify the reused path
produces the same next-token logits as a full recompute, then report prefix
hit-rate and KV saved. Finally we show re-anchoring keeps the tree bounded.
"""
import sys
import mlx.core as mx
from mlx_lm.utils import load
from mlx_lm.models.cache import make_prompt_cache

from radix_cache import RadixTree, should_reanchor
from paged_cache import BLOCK

MODEL, DATA = sys.argv[1], sys.argv[2]
PLEN = int(sys.argv[3]) if len(sys.argv) > 3 else 200
SLEN, K = 24, 4

model, tok = load(MODEL)
tokens = tok.encode(open(DATA).read())
P = tokens[:PLEN]
# K distinct candidate suffixes drawn from different parts of the corpus.
cands = [tokens[off : off + SLEN] for off in (PLEN, 5000, 9000, 13000)][:K]


def prefix_state():
    """Forward P once; return per-layer (k,v) state to cache + last logits."""
    caches = make_prompt_cache(model)
    logits = model(mx.array(P)[None], cache=caches).astype(mx.float32)
    return [c.state for c in caches], logits[:, -1, :]


def full_logits(seq):
    caches = make_prompt_cache(model)
    lo = model(mx.array(seq)[None], cache=caches).astype(mx.float32)
    return lo[:, -1, :]


def reuse_logits(prefix_kv, suffix):
    """Seed caches with cached prefix KV, compute only the suffix."""
    caches = make_prompt_cache(model)
    for c, st in zip(caches, prefix_kv):
        c.state = st  # sets keys/values + offset = len(P)
    lo = model(mx.array(suffix)[None], cache=caches).astype(mx.float32)
    return lo[:, -1, :]


tree = RadixTree()
pkv, _ = prefix_state()
tree.insert(P, pkv)

print(f"shared prefix P = {PLEN} tokens, {K} candidates x {SLEN}-token suffix\n")
max_diff = 0.0
for i, s in enumerate(cands):
    seq = P + s
    matched, cached = tree.match_prefix(seq)
    tree.record(matched, len(seq))
    base = full_logits(seq)
    reused = reuse_logits(cached, s)
    d = mx.max(mx.abs(base - reused)).item()
    max_diff = max(max_diff, d)
    print(f"  cand {i}: matched {matched}/{len(seq)} tokens from cache, "
          f"logits max|diff|={d:.2e}")

st = tree.stats()
saved_blocks = (st["hit_tokens"] // BLOCK)
print(f"\ncorrectness: reuse vs full recompute, max|diff| = {max_diff:.2e} "
      f"({'PASS' if max_diff < 5e-2 else 'FAIL'})")
print(f"prefix hit-rate : {st['hit_rate']*100:.1f}%  "
      f"({st['hit_tokens']} reused / {st['computed_tokens']} computed tokens)")
print(f"KV blocks saved : ~{saved_blocks} (block={BLOCK}) vs recomputing every candidate")
print(f"radix nodes      : {st['nodes']}")

# Re-anchoring over a simulated long session.
print("\nre-anchor demo (every 40 turns, keeping P as the anchor):")
for turn in range(1, 121):
    tree.record(PLEN, PLEN + SLEN)  # each turn reuses P
    if should_reanchor(turn, 40):
        tree.reanchor(P, pkv)
        print(f"  turn {turn}: re-anchored -> nodes={tree.stats()['nodes']} "
              f"(tree stays small as history grows)")
