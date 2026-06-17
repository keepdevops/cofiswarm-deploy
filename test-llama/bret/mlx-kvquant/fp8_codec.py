"""Simulated FP8 (e4m3fn) KV-cache codec for MLX.

MLX (this build) has no native float8 dtype, so this emulates e4m3fn rounding in
fp32 and stores the result - a fake-quant stand-in for vLLM/SGLang's real fp8 KV
cache (which needs NVIDIA fp8 tensor cores). e4m3fn: 1 sign / 4 exponent / 3
mantissa bits, max magnitude 448, with per-token scaling (the last axis is
scaled into the fp8 range, exactly like a real fp8 KV cache's per-token scale).
"""

import mlx.core as mx

E4M3_MAX = 448.0          # largest finite e4m3fn magnitude (1.75 * 2**8)
_EXP_MIN, _EXP_MAX = -6, 8  # normal unbiased exponent range
_MANT_BITS = 3


def _round_e4m3(ax: mx.array) -> mx.array:
    """Round nonneg magnitudes to the nearest e4m3fn-representable value."""
    ax = mx.clip(ax, 0.0, E4M3_MAX)
    safe = mx.maximum(ax, 1e-30)
    e = mx.clip(mx.floor(mx.log2(safe)), _EXP_MIN, _EXP_MAX)
    step = mx.power(2.0, e - _MANT_BITS)          # mantissa LSB at this exponent
    q = mx.round(ax / step) * step
    return mx.where(ax > 0, mx.clip(q, 0.0, E4M3_MAX), 0.0)


def fp8_encode_decode(x: mx.array) -> mx.array:
    """Round-trip x through per-token-scaled e4m3fn; returns dequantized tensor."""
    scale = mx.max(mx.abs(x), axis=-1, keepdims=True) / E4M3_MAX
    scale = mx.maximum(scale, 1e-12)
    return _round_e4m3(mx.abs(x / scale)) * mx.sign(x) * scale
