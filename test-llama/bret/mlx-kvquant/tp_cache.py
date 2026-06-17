"""mlx-lm cache classes that apply the real TurboQuant / PolarQuant codecs.

A TPCache behaves exactly like mlx_lm's KVCache (same growable buffers, same
update_and_fetch / state / trim contract) but every key/value chunk is passed
through a codec before being stored, so the cache holds the quantized-then-
dequantized tensors. Attention then runs on data carrying the genuine codec
error - which is what we want to measure with perplexity.

  method="turboquant" : quantize both K and V with TurboQuant-MSE at `bits`.
  method="polarquant"  : quantize K with PolarQuant; V is left in full precision
                         (PolarQuant is a key-cache method).
"""

from mlx_lm.models.cache import KVCache

import tp_codecs as tp
from fp8_codec import fp8_encode_decode

METHODS = ("turboquant", "polarquant", "fp8")


class TPCache(KVCache):
    """KVCache that stores codec-quantized K/V. Drop-in for mlx_lm generation."""

    # NOTE: deliberately not named `bits` - mlx-lm routes any cache that has a
    # `bits` attribute to its packed quantized-SDPA path. We return plain
    # dequantized tensors, so we must take the normal attention path.
    def __init__(self, method: str = "turboquant", q_bits: int = 4):
        super().__init__()
        if method not in METHODS:
            raise ValueError(f"unknown method '{method}' ({'|'.join(METHODS)})")
        self.method = method
        self.q_bits = q_bits

    def _q_keys(self, keys):
        if self.method == "turboquant":
            return tp.turboquant_encode_decode(keys, bits=self.q_bits)
        if self.method == "fp8":
            return fp8_encode_decode(keys)
        return tp.polarquant_encode_decode(keys)

    def _q_values(self, values):
        # PolarQuant is key-only; TurboQuant and fp8 quantize values too.
        if self.method == "turboquant":
            return tp.turboquant_encode_decode(values, bits=self.q_bits)
        if self.method == "fp8":
            return fp8_encode_decode(values)
        return values

    def update_and_fetch(self, keys, values):
        # Quantize the incoming chunk, then defer to the normal buffer logic.
        return super().update_and_fetch(self._q_keys(keys), self._q_values(values))

    @property
    def meta_state(self):
        return tuple(map(str, (self.method, self.q_bits)))

    @meta_state.setter
    def meta_state(self, v):
        self.method, q_bits = v
        self.q_bits = int(q_bits)


def make_caches(model, method: str, q_bits: int = 4):
    """Build one TPCache per layer for `model`."""
    n = len(model.layers) if hasattr(model, "layers") else model.args.num_hidden_layers
    return [TPCache(method=method, q_bits=q_bits) for _ in range(n)]
