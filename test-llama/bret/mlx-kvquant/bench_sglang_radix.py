"""SGLang RadixAttention parity + speed benchmark (RUN ON NVIDIA — not this Mac).

Mirrors the MLX harness scenario in run_radix.py: one shared prefix P, then K
branching candidate continuations that all share P. RadixAttention should serve
P from its prefix cache for every candidate after the first, exactly like the
MLX radix demo (which measured 89.3% hit-rate, bit-exact reuse).

Reports, for radix-cache ON vs OFF (--disable-radix-cache):
  - prefix-cache hit-rate + tokens saved  -> compare to the MLX harness 89.3%
  - wall-clock for the K candidates        -> the speedup the MLX bench can't show

IMPORTANT: SGLang needs a CUDA GPU + `pip install "sglang[all]"`. This file is
written against SGLang's offline Engine API and is UNTESTED on Apple Silicon
(SGLang does not run here). Smoke-run it on the GPU box before trusting numbers.

Usage (on the GPU host):
  python bench_sglang_radix.py --model mistralai/Mistral-7B-Instruct-v0.3 \
      --prefix-tokens 200 --candidates 4 --suffix-tokens 24
"""

import argparse
import logging
import sys
import time

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
log = logging.getLogger("bench_sglang_radix")

# Harness reference numbers (from run_radix.py) for the parity check.
MLX_HIT_RATE = 0.893
MLX_MAX_DIFF = 0.0


def build_scenario(prefix_tokens, suffix_tokens, k):
    """Return (prefix_text, [candidate_text,...]) sharing the prefix.

    Token counts are approximate (~0.75 word/token); the real counts come back
    in each response's meta_info and drive the reported metrics.
    """
    words = max(int(prefix_tokens * 0.75), 1)
    prefix = ("The following is a long shared reference context. " * 64)
    prefix = " ".join(prefix.split()[:words])
    suffixes = [
        "Summarize the key point.",
        "List three implications.",
        "Explain the main risk.",
        "Give a counterexample.",
        "Rephrase it simply.",
        "What follows next?",
    ][:k]
    cands = [f"{prefix}\n\nInstruction {i}: {s}" for i, s in enumerate(suffixes)]
    return prefix, cands


def run_mode(model, prefix, cands, max_new, disable_radix):
    """Run the scenario once; return (metrics_dict, seconds)."""
    import sglang as sgl

    label = "radix-OFF" if disable_radix else "radix-ON"
    log.info("launching SGLang Engine (%s) for %s ...", label, model)
    try:
        llm = sgl.Engine(model_path=model, disable_radix_cache=disable_radix)
    except Exception:
        log.exception("failed to launch SGLang Engine (%s)", label)
        raise

    sp = {"max_new_tokens": max_new, "temperature": 0.0}
    cached_total = prompt_total = 0
    try:
        # Warm the prefix once so candidates can hit it (no-op when radix is off).
        if not disable_radix:
            llm.generate(prefix, {"max_new_tokens": 1, "temperature": 0.0})

        t0 = time.perf_counter()
        for c in cands:
            out = llm.generate(c, sp)
            meta = out.get("meta_info", {}) if isinstance(out, dict) else {}
            cached = meta.get("cached_tokens")
            prompt = meta.get("prompt_tokens", 0)
            if cached is None:
                log.warning("meta_info has no 'cached_tokens' (SGLang version?); "
                            "hit-rate will read 0 — check `out.meta_info` fields")
                cached = 0
            cached_total += cached
            prompt_total += prompt
        secs = time.perf_counter() - t0
    finally:
        try:
            llm.shutdown()
        except Exception:
            log.exception("engine shutdown failed (%s)", label)

    hit = cached_total / prompt_total if prompt_total else 0.0
    return {"cached": cached_total, "prompt": prompt_total, "hit_rate": hit}, secs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--prefix-tokens", type=int, default=200)
    ap.add_argument("--suffix-tokens", type=int, default=24)  # advisory only
    ap.add_argument("--candidates", type=int, default=4)
    ap.add_argument("--max-new", type=int, default=16)
    args = ap.parse_args()

    if args.candidates < 2:
        log.error("need >= 2 candidates to show prefix sharing")
        sys.exit(1)

    prefix, cands = build_scenario(args.prefix_tokens, args.suffix_tokens,
                                   args.candidates)

    on, t_on = run_mode(args.model, prefix, cands, args.max_new, disable_radix=False)
    off, t_off = run_mode(args.model, prefix, cands, args.max_new, disable_radix=True)

    speedup = t_off / t_on if t_on else float("nan")
    print("\n================ SGLang RadixAttention ================")
    print(f"model      : {args.model}")
    print(f"scenario   : {args.candidates} candidates sharing a "
          f"~{args.prefix_tokens}-token prefix")
    print(f"radix ON   : hit-rate {on['hit_rate']*100:5.1f}%  "
          f"({on['cached']} cached / {on['prompt']} prompt tok)  "
          f"wall {t_on:.3f}s")
    print(f"radix OFF  : hit-rate {off['hit_rate']*100:5.1f}%  "
          f"({off['cached']} cached / {off['prompt']} prompt tok)  "
          f"wall {t_off:.3f}s")
    print(f"speedup    : {speedup:.2f}x  (radix-off / radix-on)")
    print("------------------------------------------------------")
    print(f"MLX harness reference: hit-rate {MLX_HIT_RATE*100:.1f}%, "
          f"reuse diff {MLX_MAX_DIFF:.0e} (bit-exact)")
    delta = abs(on["hit_rate"] - MLX_HIT_RATE) * 100
    verdict = "PARITY" if delta < 5.0 else f"DIVERGES ({delta:.1f}pp)"
    print(f"hit-rate parity vs MLX: {verdict}")
    print("======================================================")


if __name__ == "__main__":
    main()
