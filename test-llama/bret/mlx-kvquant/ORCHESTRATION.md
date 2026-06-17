# KV strategies for multi-server orchestration

How the KV-cache strategies in this harness map onto multi-server / multi-slot /
multi-model serving — by orchestration **mode**, by **concurrency** pattern, and
for **persistent follow-on** sessions. Companion to [`RECOMMENDATION.md`](RECOMMENDATION.md)
(which ranks the strategies themselves). Date: 2026-06-17.

## The one constraint that drives everything

**KV cache is model-specific AND quant-specific.** It cannot be shared across
different models, or across servers with different `-ctk/-ctv`, or restored into
a server whose codec differs from the one that wrote it. Consequences:

- Heterogeneous-model modes (router, cascade) win via **per-model tuning**, not
  cross-model reuse.
- Same-model modes (pipeline, flat) can do **cross-request KV sharing**.
- Any KV persistence MUST verify model + codec provenance before restore
  (`start-kvquant.sh` stamps `.server-kv.env` for exactly this).

## 1. Mode-specific wins

| Mode | Primary win | Why | Avoid |
|------|-------------|-----|-------|
| **Router** | Per-model precision tiering + paged + per-route prefix cache | Independent requests fan out to heterogeneous models; tune each server. Small models keep f16/q8 (KV tiny); large models get TurboQuant-4bit. Stable per-route preamble → `--cache-reuse`/Radix. | One global codec; cross-model KV reuse (impossible) |
| **Cascade** | Role-based precision asymmetry | Cheap filter runs on *every* request → squeeze hard (TurboQuant-4bit/2bit) for slot density. Expensive model runs rarely → spend bits (q8/FP8) for quality. | High-precision KV on the filter; handing KV small→large model |
| **Pipeline** | Slot persistence + prefix reuse, full-context codec | Stages feed forward, context accumulates; same model reuses prior KV. Pin it: `--slot-save-path` + `--cache-reuse` + Radix. Full-context codec (TurboQuant-4bit). | Sliding window (later stages need early history); recomputing the shared prefix |
| **Flat** | Throughput packing: paged + `--kv-unified` + uniform codec | Homogeneous pool, simple load-balance, independent requests. Maximize concurrent slots: paged alloc + continuous batching + one codec. Sliding window if bounded chat. | Per-request precision juggling; heavy prefix machinery (low hit-rate) |

The lever per mode: Router = heterogeneity, Cascade = volume asymmetry,
Pipeline = KV continuity, Flat = density.

## 1b. Beyond routing topologies — other mode families

Router/cascade/pipeline/flat are *request-routing* modes. Three other "mode"
families stress KV differently. None needs a new strategy — each is a new
*combination* of the same four levers (precision, block-sharing, prefix-reuse,
history-bound/persistence).

**Decoding modes** (how tokens are generated)

| Mode | KV fit |
|------|--------|
| Speculative / draft-verify | Draft KV = aggressive quant (TurboQuant-2/4bit, throwaway); target KV = high precision. Role-tiered, same as cascade. |
| Beam search | Copy-on-write block sharing of the common prefix across beams; fork on divergence. |
| Parallel sampling (`n>1`) | Prompt KV computed once, shared read-only; canonical paged+radix branch share (bit-exact, measured). |
| Structured / constrained (grammar, tool-call) | Shared prefix of the constrained region reused across attempts; SGLang's native strength. |

**Attention-shape modes** (how the model attends)

| Mode | KV fit |
|------|--------|
| Full / dense | Codec is the only KV lever; no window. |
| Sliding-window (SWA, Mistral-style) | KV bounded by architecture; pairs with dynamic-short, codec on top. |
| Hybrid global-local (Gemma-style) | Per-layer budget: window layers cheap, global layers carry cost → spend precision there. |
| MoE | Attention (hence KV) stays dense; strategy unchanged, but bigger effective models make KV quant more valuable. |

**Workload / RAG modes** (where context comes from)

| Mode | KV fit |
|------|--------|
| RAG / long-doc prefill | Prefill-dominated → prefix-cache the document across queries; full-context codec, no sliding window. |
| Prefill-heavy vs decode-heavy | Prefill-heavy → density (codec) + paging; decode-heavy → persistence + prefix reuse to skip re-prefill. |
| Multi-modal (vision/audio prefix) | Large prefix exactly reused across turns about the same input → prefix-cache is a big win; keep it high-precision (perception is sensitive). |
| Disaggregated prefill/decode | KV transfers between servers → provenance becomes a wire-format contract; quantize KV (TurboQuant-4bit) to cut transfer bandwidth. |

The pattern: every mode reduces to which of the four levers it pulls — precision
(memory/throughput-bound: MoE, prefill-heavy, disaggregated), block-sharing
(forking: beam, `n>1`, speculative, structured), prefix-reuse (shared context:
RAG, multi-modal, structured, pipeline), history-bound/persistence (temporal:
SWA vs persistent follow-ons). Disaggregated prefill/decode is the one genuinely
new wrinkle: it makes the model+codec **provenance constraint** a first-class
requirement, since KV physically moves between machines.

## 2. More than one prompt (concurrency)

Concurrency turns *conditional* strategies into *primary* ones. First split by
whether the prompts are related:

| Pattern | Example | Win | Mechanism |
|---------|---------|-----|-----------|
| **Independent prompts** | Batch of unrelated chats | Codec-for-density + paged + unified KV | Lower-bit KV → more sequences fit → bigger batch → throughput. Paging kills cross-sequence fragmentation a single prompt never exposes. |
| **Shared-prefix prompts** | Same system prompt / few-shot / document across the batch | RadixAttention block sharing + copy-on-write | Shared prefix stored **once**; sequences point at the same blocks, diverge into private blocks only on their own tokens. |

**Special case — forking one prompt** (parallel sampling `n>1`, beam search,
branching candidates): many prompts sharing 100% of a prefix. Prompt KV computed
**once**, shared read-only via the block table; branches copy-on-write on
divergence. Measured here: bit-exact reuse (0.00 diff), 89% hit-rate. Saves
~`(n-1) x prefix_len` of both KV memory and prefill compute.

Why concurrency flips priorities:
- **Paging:** single prompt = free floor; many variable-length prompts = the
  reason you don't fragment/OOM. Primary.
- **Codec precision → batch size:** halving KV bytes ~doubles concurrent slots —
  a throughput lever, not just memory.
- **Radix:** low hit-rate when independent (skip), high when prefix-shared (big
  win). Same strategy, opposite verdict, purely from concurrency.
- **Sliding window:** bounds each sequence so you can admit more of them.

## 3. Persistent follow-on sessions

A follow-on extends a prior conversation across requests (possibly after a gap,
possibly after the slot was reused). This is the **inverse of dynamic-short**:
retain and reuse history, don't discard it. Goal: never recompute what last turn
already computed.

| Strategy | Why it wins | Hook |
|----------|-------------|------|
| **KV persistence (slot save/restore)** | Restore the session's KV instead of re-prefilling the whole history every turn. Biggest saver — prefill grows linearly with conversation length otherwise. | `--slot-save-path`, `slot-cache.sh` |
| **Persistent prefix tree + re-anchoring** | Conversation is a stable extending prefix; each follow-on reuses all prior turns' KV. Re-anchor every 30-50 turns to keep the tree bounded and matchable. | Radix + `should_reanchor` |
| **KV swap/offload with LRU** | Persistent sessions >> GPU slots. Page cold sessions' blocks to CPU/disk, swap back on return (PagedAttention preemption). | paged blocks → disk |
| **Precision decay (tiered quant)** | Recent turns high-precision (q8/FP8); old/cold/persisted turns aggressively quantized (TurboQuant-4bit/2bit). Shrinks resident + on-disk footprint without dropping history. | codec by block age |

Tension and resolution: follow-ons want **full history** → **no sliding window**
here (it would silently amnesia the conversation). Bound cost instead via
re-anchoring (caps the tree), precision decay (shrinks old KV), and swap/offload
(moves idle sessions off-GPU). Dynamic-short *drops* old KV; persistent
follow-ons *demote and offload* it.

**Correctness gotcha:** restored KV is valid only if model AND codec config match
what wrote it. With persistence this provenance check is **mandatory**, not nice
— verify `.server-kv.env` (model + `KV_TYPE_K/V` + ctx) before every restore.

Mode interaction:
- **Pipeline + persistent** — natural home: per-stage KV persisted and extended;
  save/restore + re-anchor is the maximal stack.
- **Router + persistent** — sticky routing: a session must return to the *same*
  model server (its KV lives there) — needs session affinity.
- **Flat + persistent** — LRU swap essential; KV must be restorable on any slot,
  so use a shared save path across the pool.
- **Cascade + persistent** — persist only the tier actually carrying the
  conversation (usually the cheap model).

## Quick reference

| Situation | Lead with |
|-----------|-----------|
| Single stream | paged + TurboQuant-4bit |
| Many independent prompts | paged + low-bit codec for density + `--kv-unified` |
| Many shared-prefix prompts / `n>1` / beam | Radix block sharing + copy-on-write |
| Persistent follow-ons | slot save/restore + persistent Radix + re-anchor + swap; precision decay; never slide |
| Router | per-model tiering + session affinity |
| Cascade | aggressive quant on the filter, quality bits on the escalation |
| Pipeline | slot persistence + prefix reuse + full-context codec |
| Flat | density packing: paged + unified KV + uniform codec |

llama.cpp knobs in play: `--parallel`, `--cont-batching`, `--kv-unified`,
`--cache-reuse`, `--slot-save-path` (already wired in `start-kvquant.sh` /
`parallel.sh`). The `-ctk/-ctv` choice is the codec; paged/radix block-sharing is
prototyped in the MLX harness.

## Vehicle fit — where each strategy should actually run

llama-server covers ~half of these natively and **cannot** do the other half (no
custom KV codec hook, no block-table paging, no true radix tree, no KV swap).
Pick the vehicle by what you're optimizing.

| Strategy | llama-server | vLLM | SGLang | MLX harness (here) |
|----------|:---:|:---:|:---:|:---:|
| KV quant codec | ✅ built-in `-ctk/-ctv` only | ✅ fp8/int | ✅ fp8/int | ✅ **real** TurboQuant/PolarQuant/FP8 (sim) |
| Multi-slot + continuous batching | ✅ `--parallel`+`--cont-batching` | ✅ | ✅ | ⚠️ eval-only |
| Unified KV buffer | ✅ `--kv-unified` | ✅ | ✅ | n/a |
| True PagedAttention (block table, COW) | ❌ (unified KV + defrag) | ✅ native | ✅ | ✅ prototype |
| RadixAttention prefix tree + re-anchor | ⚠️ `--cache-reuse` (shift only) | ⚠️ partial | ✅ native | ✅ prototype |
| Copy-on-write branch sharing (`n>1`/beam) | ❌ | ✅ | ✅ | ✅ prototype |
| Persistent follow-ons (save/restore) | ✅ `--slot-save-path` | ✅ | ✅ | ⚠️ via `state` |
| KV swap/offload to CPU/disk (LRU) | ❌ | ✅ | ✅ | ❌ |
| Precision decay (tiered by age) | ❌ single codec | ⚠️ | ⚠️ | ✅ prototype |
| Real FP8 tensor-core speedup | ❌ | ✅ (NVIDIA) | ✅ (NVIDIA) | ❌ (simulated) |
| Runs on Apple Silicon / no GPU | ✅ | ❌ | ❌ | ✅ |

Verdict — these are **two stacks, not one**:

- **llama-server** = GGUF / edge / single-box serving. Covers codec + multi-slot
  + persistence — most of what one machine needs. Weakest on paging, radix, swap.
- **SGLang** (RadixAttention-first) or **vLLM** (PagedAttention-first) = the
  production home for the multi-prompt and persistent-follow-on wins above, on
  NVIDIA. SGLang matches the router/cascade/pipeline framing most directly; vLLM
  leads on paging + swap. Both give real FP8.
- **MLX harness (this repo)** = the research bench. Only place to run the *actual*
  TurboQuant/PolarQuant algorithms + paged + radix + sliding window on a Mac;
  quality-faithful (fake-quant), no kernel speedups. Validate a strategy here
  (bit-exact / PPL evidence) before committing it to a production engine.

| Optimizing for | Best vehicle |
|----------------|--------------|
| GGUF models, local/edge, simplicity | llama-server |
| Production paging + swap + real FP8 (NVIDIA) | vLLM |
| Production radix prefix sharing, structured gen (NVIDIA) | SGLang |
| Apple Silicon / researching the real algorithms | MLX harness |
