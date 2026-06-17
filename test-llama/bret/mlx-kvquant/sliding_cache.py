"""Sliding-window KV cache with a codec, for the dynamic / short-context regime.

Subclasses mlx-lm's RotatingKVCache (which already implements a correct sliding
window: bounded buffer, rotation, RoPE positions, masking) and applies a KV
codec to each written chunk - so we get window + quantization without
reimplementing the fiddly window/mask logic. Default codec is simulated FP8.

For highly dynamic, short-context chat (fresh content per call, low prefix-cache
hit rate) this is the operative cache: a sliding window caps KV memory at
max_size tokens, FP8 halves the bytes, and there is no prefix tree to maintain.
"""

from mlx_lm.models.cache import RotatingKVCache

import tp_codecs as tp
from fp8_codec import fp8_encode_decode


class CodecRotatingCache(RotatingKVCache):
    """RotatingKVCache that codec-quantizes K/V on write (batch handled by base)."""

    def __init__(self, max_size: int, keep: int = 4,
                 method: str = "fp8", q_bits: int = 4):
        super().__init__(max_size=max_size, keep=keep)
        if method not in ("fp8", "turboquant"):
            raise ValueError(f"sliding-window codec must be fp8|turboquant, got '{method}'")
        self.method, self.q_bits = method, q_bits

    def _q(self, x):
        if self.method == "fp8":
            return fp8_encode_decode(x)
        return tp.turboquant_encode_decode(x, bits=self.q_bits)

    def update_and_fetch(self, keys, values):
        return super().update_and_fetch(self._q(keys), self._q(values))
