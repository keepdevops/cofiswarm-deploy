"""Faithful TurboQuant and PolarQuant KV-cache codecs in MLX.

These implement the *actual* algorithms (not the llama.cpp -ctk/-ctv stand-ins):

  TurboQuant  (arXiv:2504.19874) - randomized Hadamard rotation makes every
              coordinate follow a fixed distribution, then a data-oblivious
              Lloyd-Max scalar quantizer (fit once on that distribution) encodes
              each coordinate. MSE variant (no QJL product-correction bit).

  PolarQuant  (arXiv:2502.02617) - random preconditioning (same Hadamard
              rotation), then a recursive polar transform (adjacent dims ->
              radius+angle) whose angles are tightly distributed and cheap to
              quantize. A key-cache method: keys are encoded, values are not.

This is a *fake-quant* implementation for quality evaluation: encode() returns a
dequantized array carrying exactly the algorithm's reconstruction error, so the
resulting perplexity reflects real codec quality. It does not pack bits or use a
fused decode kernel (those give the speed/memory wins; they are CUDA/Triton in
the reference repos and out of scope for an MLX eval harness).

All codecs operate on the last axis (= head_dim), which must be a power of two.
"""

import functools
import math

import mlx.core as mx
import numpy as np

# --------------------------------------------------------------------------- #
# Randomized Hadamard transform (the shared "random rotation")
# --------------------------------------------------------------------------- #


@functools.lru_cache(maxsize=8)
def _hadamard(d: int) -> mx.array:
    """Normalized Sylvester-Hadamard matrix H (d x d), H @ H == I."""
    if d & (d - 1) != 0:
        raise ValueError(f"head_dim must be a power of two for Hadamard RHT, got {d}")
    h = np.array([[1.0]], dtype=np.float32)
    while h.shape[0] < d:
        h = np.block([[h, h], [h, -h]])
    return mx.array(h / math.sqrt(d))


@functools.lru_cache(maxsize=8)
def _signs(d: int, seed: int = 0) -> mx.array:
    """Fixed random +/-1 preconditioning vector (data-oblivious, seeded)."""
    rng = np.random.default_rng(seed)
    return mx.array(rng.choice([-1.0, 1.0], size=d).astype(np.float32))


def rht(x: mx.array) -> mx.array:
    """Randomized Hadamard transform along the last axis."""
    d = x.shape[-1]
    return (x * _signs(d)) @ _hadamard(d)


def irht(y: mx.array) -> mx.array:
    """Inverse RHT (H is symmetric-orthogonal, so just reapply then unsign)."""
    d = y.shape[-1]
    return (y @ _hadamard(d)) * _signs(d)


# --------------------------------------------------------------------------- #
# TurboQuant (MSE variant)
# --------------------------------------------------------------------------- #


@functools.lru_cache(maxsize=16)
def _lloyd_max_levels(d: int, bits: int, samples: int = 20000) -> mx.array:
    """Data-oblivious Lloyd-Max levels for an RHT-ed unit vector's coordinates.

    Sample random unit vectors, RHT them, and fit 2**bits reproduction levels to
    the empirical coordinate distribution with Lloyd's algorithm. Cached per
    (d, bits) so the cost is paid once per process.
    """
    rng = np.random.default_rng(1234)
    v = rng.standard_normal((samples, d)).astype(np.float32)
    v /= np.linalg.norm(v, axis=1, keepdims=True)
    coords = np.asarray(rht(mx.array(v))).reshape(-1)

    k = 2 ** bits
    # Init levels on quantiles of the (symmetric) distribution.
    levels = np.quantile(coords, np.linspace(0.0, 1.0, k + 2)[1:-1]).astype(np.float32)
    for _ in range(50):
        bounds = (levels[:-1] + levels[1:]) / 2.0
        idx = np.searchsorted(bounds, coords)
        new = levels.copy()
        for j in range(k):
            sel = coords[idx == j]
            if sel.size:
                new[j] = sel.mean()
        if np.allclose(new, levels, atol=1e-6):
            levels = new
            break
        levels = new
    return mx.array(np.sort(levels))


def _quantize_to_levels(y: mx.array, levels: mx.array) -> mx.array:
    """Nearest-level scalar quantization (returns dequantized values)."""
    # |y - levels| over a new trailing axis, pick nearest.
    idx = mx.argmin(mx.abs(y[..., None] - levels), axis=-1)
    return mx.take(levels, idx)


def turboquant_encode_decode(x: mx.array, bits: int = 4) -> mx.array:
    """Round-trip x through TurboQuant-MSE; returns the dequantized tensor."""
    gamma = mx.linalg.norm(x, axis=-1, keepdims=True)
    gamma = mx.maximum(gamma, 1e-8)
    u = x / gamma
    y = rht(u)
    y_hat = _quantize_to_levels(y, _lloyd_max_levels(x.shape[-1], bits))
    return irht(y_hat) * gamma


# --------------------------------------------------------------------------- #
# PolarQuant (recursive polar transform, key cache)
# --------------------------------------------------------------------------- #

_TWO_PI = 2.0 * math.pi


def _uniform_qdq(a: mx.array, lo, hi, bits: int) -> mx.array:
    """Uniform quantize->dequantize a into [lo, hi) with 2**bits bins (bin centers)."""
    n = 2 ** bits
    step = (hi - lo) / n
    idx = mx.clip(mx.floor((a - lo) / step), 0, n - 1)
    return lo + (idx + 0.5) * step


def polarquant_encode_decode(x: mx.array, levels: int = 4,
                             angle_bits1: int = 4, angle_bits_deep: int = 2,
                             radius_bits: int = 4) -> mx.array:
    """Round-trip a KEY tensor through PolarQuant; returns the dequantized tensor.

    Adjacent dims (even, odd) form a pair -> (radius, angle). Radii feed the next
    level recursively. Level-1 angles are ~uniform on [0, 2pi) (4 bits); deeper
    angles concentrate near pi/4 (2 bits). The final radii are kept in fp16.
    """
    d = x.shape[-1]
    max_levels = int(math.log2(d))
    levels = min(levels, max_levels)

    y = rht(x)
    cur = y
    angles_q = []  # dequantized angle arrays, outer level first
    for lvl in range(levels):
        xe = cur[..., 0::2]
        xo = cur[..., 1::2]
        radius = mx.sqrt(xe * xe + xo * xo)
        angle = mx.arctan2(xo, xe)
        angle = mx.where(angle < 0, angle + _TWO_PI, angle)  # -> [0, 2pi)
        if lvl == 0:
            a_q = _uniform_qdq(angle, 0.0, _TWO_PI, angle_bits1)
        else:
            lo = mx.min(angle)
            hi = mx.max(angle) + 1e-6
            a_q = _uniform_qdq(angle, lo, hi, angle_bits_deep)
        angles_q.append(a_q)
        cur = radius  # recurse on the radii

    # Quantize the final radii with per-tensor min/max (uniform, radius_bits).
    r_lo = mx.min(cur)
    r_hi = mx.max(cur) + 1e-6
    cur = _uniform_qdq(cur, r_lo, r_hi, radius_bits)

    # Reconstruct from the deepest level back up to the full vector.
    for lvl in reversed(range(levels)):
        a_q = angles_q[lvl]
        xe = cur * mx.cos(a_q)
        xo = cur * mx.sin(a_q)
        out = mx.zeros(xe.shape[:-1] + (xe.shape[-1] * 2,), dtype=xe.dtype)
        # interleave even/odd back
        idx_e = mx.arange(0, out.shape[-1], 2)
        idx_o = mx.arange(1, out.shape[-1], 2)
        out[..., idx_e] = xe
        out[..., idx_o] = xo
        cur = out

    return irht(cur)
