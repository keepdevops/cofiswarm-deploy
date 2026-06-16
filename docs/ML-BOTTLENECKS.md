# ML Bottlenecks — Inference Focus & Cofiswarm Mapping

Reference for **serving-time** bottlenecks (cost, quality, speed, memory) and how
they map to Matrix Swarm components. Training bottlenecks are summarized only
where they affect future fine-tune jobs.

**Related:** [architecture-flow.md](./architecture-flow.md) · [sprints/SCALE-GATES.md](./sprints/SCALE-GATES.md)

---

## Optimization goals

| Goal | Inference meaning in this stack |
|------|----------------------------------|
| **Cost** | Fewer agent calls, smaller quant, shorter context, router vs flat |
| **Quality** | Model choice, synthesis policy, RAG, less aggressive KV quant |
| **Speed** | Parallel slots, speculative decode, cascade deadline, flash-attn |
| **Memory** | `ctx_cap ÷ slots`, KV quant, eviction, MLX serialization |

---

## Training vs inference — what applies here

| Bottleneck | Training | Inference (Cofiswarm) | Priority |
|------------|:--------:|:---------------------:|:--------:|
| KV cache | Low | **Critical** | ★★★★★ |
| Attention O(N²) | **Critical** | High (prefill) | ★★★★☆ |
| Activation memory | **Critical** | Negligible | ★☆☆☆☆ |
| GPU communication | **Critical** | Medium (multi-GPU / MoE) | ★★☆☆☆ |
| Optimizer state | **Critical** | N/A | — |
| Data supply | **Critical** | N/A (RAG = knowledge) | ★★☆☆☆ |
| Inference throughput | N/A | **Critical** | ★★★★★ |
| MoE routing | High | Low (dense GGUF on M3) | ★★☆☆☆ |

---

## 1. KV cache

### Description

Transformers reuse **Key** and **Value** tensors from prior tokens during decode.
Without a cache, every new token would recompute attention over the full prefix.

| Phase | Work | Cost |
|-------|------|------|
| **Prefill** | Process full prompt; build KV | High (compute + memory write) |
| **Decode** | One token; attend to cached K/V | Lower per token |

### Memory (order of magnitude)

```
KV_bytes ≈ 2 × layers × kv_heads × head_dim × seq_len × bytes_per_elem
         (× batch_slots for continuous batching)
```

Per-slot budget in this stack:

```
per_slot_kv ≈ ctx_cap ÷ parallel_slots
```

See [architecture-flow.md §1](./architecture-flow.md) — agents sharing a model
path share one server; `parallel` = slot count.

### Issues

- Grows **linearly** with sequence length
- Dominates RAM on long context + many slots
- K/V **more sensitive** to quant than weights
- Cache migration across GPUs is expensive (not primary on unified-memory M3)
- Hard to “edit” past tokens without rebuild

### Solutions

| Solution | Cost | Speed | Quality | Memory | Cofiswarm |
|----------|------|-------|---------|--------|-----------|
| GQA / MQA (in model) | — | ↑ | model-dep | ↓ | model choice |
| `--cache-type-k/v` quant | ↓ | ~ | small ↓ | ↓ 2–4× | `swarm-config` `extra_args` |
| TurboQuant (MLX) | ↓ | ~ | tune | ↓ | `infer-mlx` pilot |
| PagedAttention | — | ↑ util | — | ↓ frag | vLLM path |
| Sliding window | ↓ | ↑ | ↓ recall | ↓ | model/arch |
| Slot eviction | — | ↑ reuse | warm-cache loss | ↓ peak | `kv_auto_clear`, future `kvpool` |
| Fewer parallel slots | ↓ contention | ↓ | — | ↑ per slot | deploy profile |

### Component map

| Concern | Today | Target repo |
|---------|-------|-------------|
| Per-slot KV budget | `ctx_cap`, `--parallel` | `infer-*`, `config` |
| Pressure probe | `GET /api/pressure` | `slot-manager` |
| Auto / partial clear | `kv_auto_clear.h` | `kvpool` + `slot-manager` |
| Token budget gate | `kv_token_budget`, `agent_client_pool` | `slot-manager` |
| Importance eviction | `kv_importance_indexer.h` | `kvpool` |

**Pressure thresholds (code defaults):**

| Level | `usage` | Action |
|-------|---------|--------|
| Nominal | &lt; 0.60 | None |
| Proactive | ≥ 0.60 | Partial evict bottom 30% by importance |
| Full clear | ≥ 0.75 | Full KV clear (if auto_clear enabled + topic divergence) |

---

## 2. Attention complexity

Self-attention over length N:

- **Prefill compute** ∝ N²
- **Decode per step** ∝ N (with KV cache)

| Context vs 8k | Relative prefill |
|---------------|------------------|
| 32k | ~16× |
| 128k | ~256× |

### Issues (inference)

- Long prompts dominate latency before multi-agent fan-out
- Router classifier + RAG embed add fixed overhead on top

### Solutions

| Solution | Inference fit |
|----------|---------------|
| FlashAttention | `--flash-attn` on llama Metal |
| Prompt truncation | `max_input_tokens` per agent |
| RAG chunks vs huge prompt | `rag.top_k`, per-agent `use_rag` |
| Router mode | Skip irrelevant agents |

### Component map

| Concern | File / API |
|---------|------------|
| Flash attn | `proxy_configure_spawn_args.h` |
| Input cap | `Agent::max_input_tokens` |
| RAG inject | coordinator pre-dispatch; future `dispatch` |
| Mode fan-out | `coordinator_routes_architect_stream_modes.cpp` |

---

## 3. Activation memory

**Training only.** Activations ∝ batch × seq × hidden × layers.

Relevant if you add fine-tune jobs (`cofiswarm-convert` / future train sidecar).
Not a serving bottleneck for Matrix Swarm today.

---

## 4. GPU / device communication

**Training:** all-reduce dominates at scale.

**Inference (this stack):**

| Platform | Bottleneck |
|----------|------------|
| M3 Metal | Unified memory heap; MLX **single-lane** serialize |
| Multi-GPU llama/vLLM | Tensor parallel, KV moves |
| MoE (Kimi-class) | Expert parallelism all-to-all |

`backend_router` (llama ↔ mlx fallback) is a **reliability** path, not throughput.

---

## 5. Optimizer state

Adam-style state ≈ **4× parameter memory**. Training-only.

---

## 6. Data bottleneck

Frontier **pretraining** constraint. For serving:

- **RAG** = external memory (reduces need for extreme KV context)
- **Agent loops** (OpenCode) = synthetic task data, not weight updates

---

## 7. Inference throughput

Often **memory-bandwidth bound**:

```
throughput ∝ memory_bandwidth / bytes_read_per_token
```

### Multi-agent multiplier

| Mode | Agent calls per user prompt | Cost multiplier |
|------|----------------------------|-----------------|
| `flat` | All deployed agents | N |
| `cascade` | N proposers + 1 synthesizer | N + 1 |
| `pipeline` | Chain length | stages |
| `router` | ≤ `max_select` | ≤ max_select |

Default coordinator profile uses `router` with `max_select: 2` — explicit
**cost/speed** optimization.

### Solutions

| Solution | Config |
|----------|--------|
| Continuous batching | `--parallel N` per model server |
| Weight quant | Q4_K_M GGUF, MLX 4-bit |
| Speculative decode | `draft_model`, `draft_max` |
| Router / smaller roster | `coordinator.modes.router` |
| Cascade deadline | `MATRIX_CASCADE_AGENT_DEADLINE_SECS` (default 90) |

---

## 8. Mixture of Experts (MoE)

Routing activates k of E experts per token. System issues: load balance, expert
comm, collapse.

| Deployment | MoE impact |
|------------|------------|
| M3 dense GGUF 7B–8B | **Low** |
| mlx-scout 1B | **Low** |
| Self-host Kimi K2.x | **Very high** — multi-GPU vLLM/SGLang |
| Moonshot API | Opaque / their ops |

---

## Pareto rules (inference)

1. **Memory ↔ speed:** more `--parallel` slots → higher throughput, **less** KV per slot.
2. **Quality ↔ memory:** KV quant saves RAM; hurts more than weight quant.
3. **Cost ↔ speed:** flat mode ≈ **N×** single-agent cost.
4. **Quality ↔ speed:** cascade waits for slowest proposer (deadline trims tail).

---

## SCALE sprint linkage

Agent scale-up sprints (**SCALE-1 … SCALE-7**) gate on KV stability before adding
load. See [sprints/SCALE-GATES.md](./sprints/SCALE-GATES.md).

| Gate metric | Source |
|-------------|--------|
| Endpoint `usage` (0–1) | `GET /api/pressure` → `snapshot_pressure` |
| `kv_pressure` in run meta | Stream / history envelope |
| OOM / MLX lane block | `agent_logs/`, coordinator stderr |
| Cascade timeout rate | Agents exceeding `MATRIX_CASCADE_AGENT_DEADLINE_SECS` |
| p95 time-to-first-token | Manual / observer plugin |

**Do not advance SCALE-N** if any endpoint sustains `usage ≥ 0.75` under the
sprint nominal workload (see SCALE-GATES §3).

---

## Knob quick reference

| Knob | Where | Bottleneck |
|------|-------|------------|
| `ctx_cap`, `context` | `swarm-config.json` | KV memory |
| `--cache-type-k/v` | agent `extra_args` | KV memory / quality |
| `kv_token_budget` | agent / coordinator | Throughput vs memory |
| `max_tokens`, `max_input_tokens` | agent | Speed / cost |
| `max_select` | `coordinator.modes.router` | Cost |
| `MATRIX_CASCADE_AGENT_DEADLINE_SECS` | `matrix-env.sh` | Speed vs quality |
| `auto_clear_kv.*` | coordinator config | KV pressure |
| `rag.top_k` | `config/coordinator.json` | Attention / prefill |

---

## Source map

| Concern | File |
|---------|------|
| KV pressure snapshot | `yyyyy/cpp_core/src/pressure_snapshot.cpp` |
| Auto / proactive clear | `yyyyy/cpp_core/src/kv_auto_clear.h` |
| KV ops / erase | `yyyyy/cpp_core/src/coordinator_kv_ops.cpp` |
| Per-port concurrency | `yyyyy/cpp_core/src/agent_client_pool.cpp` |
| Spawn / parallel / cache types | `yyyyy/cpp_core/src/proxy_configure_spawn_args.h` |
| Synthesis budget | `yyyyy/cpp_core/src/synthesis_budget.cpp` |
| Architecture flow | `docs/architecture-flow.md` |
