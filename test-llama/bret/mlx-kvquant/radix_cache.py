"""RadixAttention-style prefix cache for the MLX harness.

A compressed radix tree over token prefixes (SGLang's RadixAttention idea): each
node can hold the per-layer KV for the prefix ending at it, so branching
candidate paths that share a leading context reuse that context's KV instead of
recomputing it. Supports:

  match_prefix(tokens) -> (matched_len, cached_kv)  longest cached ancestor
  insert(tokens, kv)                                cache a prefix's KV
  reanchor(anchor_tokens)                           reset the tree to a fresh
                                                    root holding only `anchor`,
                                                    run every 30-50 turns so the
                                                    shared prefix stays small and
                                                    matchable as history grows

`kv` is whatever the caller wants to reuse - here a per-layer list of (k, v)
mlx arrays for the prefix. Forking is implicit: two sequences sharing a prefix
both match the same cached node, so they share its KV with zero extra work.
"""

from typing import List, Optional, Tuple


class _Node:
    __slots__ = ("children", "kv", "plen", "last_used")

    def __init__(self, plen: int = 0):
        self.children = {}      # first_token -> (segment_tuple, child_node)
        self.kv = None          # cached KV for the prefix ending here, or None
        self.plen = plen        # length of the prefix ending at this node
        self.last_used = 0


class RadixTree:
    def __init__(self):
        self.root = _Node(0)
        self.clock = 0
        self.hit_tokens = 0
        self.computed_tokens = 0

    # -- lookup ----------------------------------------------------------------
    def match_prefix(self, tokens) -> Tuple[int, Optional[list]]:
        """Longest cached prefix of `tokens`. Returns (matched_len, cached_kv)."""
        node, i = self.root, 0
        best_len, best_kv = 0, None
        while i < len(tokens):
            edge = node.children.get(tokens[i])
            if edge is None:
                break
            seg, child = edge
            j = 0
            while j < len(seg) and i + j < len(tokens) and seg[j] == tokens[i + j]:
                j += 1
            i += j
            if j < len(seg):
                break  # diverged mid-edge: no node boundary here
            node = child
            if node.kv is not None:
                best_len, best_kv = i, node.kv
                node.last_used = self.clock
        return best_len, best_kv

    # -- insertion (with edge splitting) --------------------------------------
    def insert(self, tokens, kv) -> None:
        node, i = self.root, 0
        while i < len(tokens):
            key = tokens[i]
            edge = node.children.get(key)
            if edge is None:
                child = _Node(len(tokens))
                node.children[key] = (tuple(tokens[i:]), child)
                node = child
                i = len(tokens)
                break
            seg, child = edge
            j = 0
            while j < len(seg) and i + j < len(tokens) and seg[j] == tokens[i + j]:
                j += 1
            if j < len(seg):
                # split the edge at j
                mid = _Node(i + j)
                node.children[key] = (seg[:j], mid)
                mid.children[seg[j]] = (seg[j:], child)
                node = mid
                i += j
                if i >= len(tokens):
                    break
                # add remaining tokens as a new branch
                leaf = _Node(len(tokens))
                mid.children[tokens[i]] = (tuple(tokens[i:]), leaf)
                node = leaf
                i = len(tokens)
                break
            i += j
            node = child
        node.kv = kv
        node.plen = len(tokens)
        node.last_used = self.clock

    # -- accounting / lifecycle -----------------------------------------------
    def record(self, matched_len: int, total_len: int) -> None:
        """Tally a request: matched_len reused, the rest recomputed."""
        self.clock += 1
        self.hit_tokens += matched_len
        self.computed_tokens += max(total_len - matched_len, 0)

    def reanchor(self, anchor_tokens, anchor_kv=None) -> None:
        """Drop the whole tree, keep only `anchor_tokens` as the new root prefix.

        Keeps the shared prefix small and matchable as the session's tool history
        grows; call every 30-50 turns. Loud no-op if the anchor is empty.
        """
        if not anchor_tokens:
            raise ValueError("reanchor requires a non-empty anchor prefix")
        self.root = _Node(0)
        if anchor_kv is not None:
            self.insert(anchor_tokens, anchor_kv)

    def hit_rate(self) -> float:
        tot = self.hit_tokens + self.computed_tokens
        return self.hit_tokens / tot if tot else 0.0

    def stats(self) -> dict:
        return {
            "hit_tokens": self.hit_tokens,
            "computed_tokens": self.computed_tokens,
            "hit_rate": self.hit_rate(),
            "nodes": self._count(self.root),
        }

    def _count(self, node) -> int:
        return 1 + sum(self._count(c) for _, c in node.children.values())


SHOULD_REANCHOR_EVERY = (30, 50)  # turn window to re-anchor the prefix


def should_reanchor(turn: int, every: int = 40) -> bool:
    return turn > 0 and turn % every == 0
