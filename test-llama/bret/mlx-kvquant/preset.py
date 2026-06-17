"""Regime -> KV-cache-stack presets.

Different serving regimes want different stacks. This maps a named regime to a
per-layer cache factory plus a short rationale, so callers don't re-derive the
choice each time. Built on the harness pieces: TPCache (codecs), PagedTPCache
(paged blocks), CodecRotatingCache (sliding window), RadixTree (prefix reuse).
"""

from tp_cache import TPCache
from paged_cache import PagedTPCache
from sliding_cache import CodecRotatingCache


def _n_layers(model):
    return len(model.layers)


def dynamic_short(model, window: int = 1024):
    """Highly dynamic / short-context chat: paged + FP8 KV + sliding window.

    Fresh content per call => prefix-cache hit rate is low, so skip the radix
    tree entirely (its bookkeeping would cost more than it saves). FP8 is
    near-lossless and halves bytes; the sliding window caps memory at `window`
    tokens. GQA models are fine here - MLA's KV-compression edge mostly shows
    above ~32K context, which this regime never reaches.
    """
    n = _n_layers(model)
    return [CodecRotatingCache(max_size=window, keep=4, method="fp8") for _ in range(n)]


def long_context_branching(model, method: str = "turboquant", q_bits: int = 4):
    """Long shared context + branching candidates: paged + codec + (use radix).

    Here a prefix cache pays off; pair PagedTPCache with a RadixTree at the call
    site (see run_radix.py). Codec keeps per-token KV small over long sequences.
    """
    n = _n_layers(model)
    return [PagedTPCache(method=method, q_bits=q_bits) for _ in range(n)]


REGIMES = {
    "dynamic-short": dynamic_short,
    "long-context": long_context_branching,
}


def describe():
    return (
        "dynamic-short : paged + FP8 KV + sliding window; NO prefix cache "
        "(low hit rate); GQA fine (<32K).\n"
        "long-context  : paged + codec + RadixAttention prefix reuse."
    )
