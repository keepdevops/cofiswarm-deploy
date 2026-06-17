"""PagedAttention-style block-table KV cache for the MLX codec harness.

A faithful demo of vLLM's *memory-management* idea (Kwon et al. 2023): the KV
cache is split into fixed-size blocks; a per-sequence block table maps logical
token positions to physically non-contiguous blocks, so growth never needs a
contiguous reallocation and there is no external fragmentation. Internal
fragmentation is bounded by one block per sequence.

What this is NOT: vLLM's fused paged-attention CUDA kernel. MLX has no paged
SDPA, so for the attention step we *gather* the blocks into a logically
contiguous tensor via the block table. That keeps results identical to the
contiguous cache while still exercising real block allocation / a block table /
fragmentation accounting. Same "fake-quant" spirit as the rest of this harness:
we measure the management scheme, not a custom kernel's speed.

Composes with the TurboQuant / PolarQuant codecs in tp_codecs.py: each written
chunk is codec-quantized before it lands in a block.
"""

import math

import mlx.core as mx
import numpy as np
from mlx_lm.models.cache import _BaseCache, create_attention_mask

import tp_codecs as tp

BLOCK = 16  # tokens per block (vLLM default is 16)


class BlockPool:
    """Owns one physical KV store and hands out fixed-size token blocks.

    Storage is [n_kv_heads, num_blocks * BLOCK, head_dim]; block id b owns the
    slot range [b*BLOCK, (b+1)*BLOCK). Freed blocks return to a free list and are
    reused, so identical workloads never grow the pool unbounded.
    """

    def __init__(self, n_kv_heads: int, head_dim: int, dtype, block: int = BLOCK):
        self.h, self.d, self.dtype, self.block = n_kv_heads, head_dim, dtype, block
        self.store = mx.zeros((n_kv_heads, 0, head_dim), dtype=dtype)
        self.num_blocks = 0
        self.free = []

    def allocate(self) -> int:
        if self.free:
            return self.free.pop()
        bid = self.num_blocks
        self.num_blocks += 1
        pad = mx.zeros((self.h, self.block, self.d), dtype=self.dtype)
        self.store = mx.concatenate([self.store, pad], axis=1)
        return bid

    def free_blocks(self, ids):
        self.free.extend(ids)

    def write(self, block_id: int, slot: int, chunk: mx.array):
        """Write chunk [H, n, D] into block_id starting at slot."""
        a = block_id * self.block + slot
        self.store[:, a : a + chunk.shape[1], :] = chunk.astype(self.dtype)

    def gather(self, abs_slots: mx.array) -> mx.array:
        """Gather logical-order tokens (abs_slots: [seq]) -> [H, seq, D]."""
        return mx.take(self.store, abs_slots, axis=1)


class PagedTPCache(_BaseCache):
    """mlx-lm cache with a paged block table + codec quantization (batch=1)."""

    def __init__(self, method: str = "turboquant", q_bits: int = 4, block: int = BLOCK):
        if method not in ("turboquant", "polarquant"):
            raise ValueError(f"unknown method '{method}' (turboquant|polarquant)")
        self.method, self.q_bits, self.block = method, q_bits, block
        self.kpool = self.vpool = None
        self.block_table = []  # logical block index -> physical block id
        self.offset = 0

    # -- codecs (mirror tp_cache.TPCache) --------------------------------------
    def _q_keys(self, keys):
        if self.method == "turboquant":
            return tp.turboquant_encode_decode(keys, bits=self.q_bits)
        return tp.polarquant_encode_decode(keys)

    def _q_values(self, values):
        if self.method == "turboquant":
            return tp.turboquant_encode_decode(values, bits=self.q_bits)
        return values  # PolarQuant is key-only

    def _abs_slots(self, n: int) -> mx.array:
        bt, blk = self.block_table, self.block
        idx = [bt[t // blk] * blk + (t % blk) for t in range(n)]
        return mx.array(np.asarray(idx, dtype=np.uint32))

    def update_and_fetch(self, keys, values):
        if keys.shape[0] != 1:
            raise ValueError(f"PagedTPCache supports batch=1, got B={keys.shape[0]}")
        qk = self._q_keys(keys)[0]      # [H, L, Dk]
        qv = self._q_values(values)[0]  # [H, L, Dv]
        H, L, Dk = qk.shape
        if self.kpool is None:
            # Match TPCache: store the codec output in its own dtype (no extra
            # rounding), so paged and contiguous caches are bit-for-bit equal.
            self.kpool = BlockPool(H, Dk, qk.dtype, self.block)
            self.vpool = BlockPool(H, qv.shape[-1], qv.dtype, self.block)

        prev, new = self.offset, self.offset + L
        needed = math.ceil(new / self.block)
        while len(self.block_table) < needed:
            bid = self.kpool.allocate()
            self.vpool.allocate()  # kept in lockstep -> same id
            self.block_table.append(bid)

        # Write the chunk block-by-block (non-contiguous physical layout).
        p, src = prev, 0
        while p < new:
            bi, slot = p // self.block, p % self.block
            bid = self.block_table[bi]
            n = min(self.block - slot, new - p)
            self.kpool.write(bid, slot, qk[:, src : src + n, :])
            self.vpool.write(bid, slot, qv[:, src : src + n, :])
            p += n; src += n

        self.offset = new
        slots = self._abs_slots(new)
        return self.kpool.gather(slots)[None], self.vpool.gather(slots)[None]

    # -- fragmentation accounting ---------------------------------------------
    def frag_stats(self, contiguous_step: int = 256) -> dict:
        """Paged vs contiguous allocation for the current sequence length."""
        paged_alloc = len(self.block_table) * self.block
        contig_alloc = math.ceil(self.offset / contiguous_step) * contiguous_step
        return {
            "tokens_used": self.offset,
            "paged_blocks": len(self.block_table),
            "paged_alloc_tokens": paged_alloc,
            "paged_waste": paged_alloc - self.offset,
            "contig_alloc_tokens": contig_alloc,
            "contig_waste": contig_alloc - self.offset,
        }

    # -- _BaseCache plumbing ---------------------------------------------------
    def __len__(self):
        return self.offset

    def is_trimmable(self):
        return True

    def trim(self, n):
        n = min(self.offset, n)
        self.offset -= n
        # Release whole blocks no longer needed (loud about partial-block waste).
        keep = math.ceil(self.offset / self.block)
        if keep < len(self.block_table):
            freed = self.block_table[keep:]
            self.kpool.free_blocks(freed)
            self.vpool.free_blocks(freed)
            self.block_table = self.block_table[:keep]
        return n

    def make_mask(self, *args, **kwargs):
        return create_attention_mask(*args, offset=self.offset, **kwargs)
