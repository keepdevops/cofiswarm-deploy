# Migration sprints — device setup & file mapping

Linear plan to scaffold **all** `cofiswarm-*` repos on this device (M3 Max),
create FHS + `test/standalone` trees, and **copy** files from `cofiswarmdev`
into the correct targets.

**Device roots (create once):**

| Path | Purpose |
|------|---------|
| `~/cofiswarm/repos/` | Git clone / scaffold for each repo |
| `~/cofiswarm/fhs/` | Host standalone runtime (mirrors `/opt`, `/etc`, `/var`, `/run`) |
| `~/cofiswarmdev/` | Monorepo source (unchanged until cutover) |

**Conventions:** [REPO-STANDARD-LAYOUT.md](./REPO-STANDARD-LAYOUT.md) · [SCALE-GATES.md](./sprints/SCALE-GATES.md)

---

## Sprint 0 — Device roots & scaffold script

**Goal:** Parent dirs, helper script, monorepo `test/standalone` verified.

**Commands:**

```bash
mkdir -p ~/cofiswarm/{repos,fhs}
install -d -m 0750 ~/cofiswarm/fhs/{opt/cofiswarm,etc/cofiswarm,var/lib/cofiswarm,var/log/cofiswarm,run/cofiswarm}

cd ~/cofiswarmdev
./test/scripts/assert-layout.sh
```

**Deliverables:**

| Create | Source |
|--------|--------|
| `~/cofiswarm/repos/` | — |
| `~/cofiswarm/fhs/{opt,etc,var/lib,var/log,run}/cofiswarm/` | REPO-STANDARD-LAYOUT §2 |
| `cofiswarmdev/test/standalone/` | already scaffolded |

**Gate:** `assert-layout.sh` exits 0.

---

## Sprint 1 — `cofiswarm-deploy` + `cofiswarm-common` + `cofiswarm-docs`

**Goal:** Meta repo, shared contracts, doc migration.

### 1a. Scaffold `~/cofiswarm/repos/cofiswarm-deploy`

```
cofiswarm-deploy/
├── repos.json
├── Makefile
├── .env.example
├── compose/docker-compose.yml
├── compose/profiles/{8gb,16gb,32gb}.yml
├── compose/test.integration.yml
├── config/                              # render target → ~/cofiswarm/fhs/etc/cofiswarm
├── grafana/dashboards/
├── systemd/cofiswarm.target
├── scripts/{install-host.sh,render-config.sh,backup-state.sh}
├── docs/{MIGRATION.md,DEPRECATIONS.md}
└── test/standalone/                     # full-stack FHS union (all roles)
    ├── opt/cofiswarm/
    ├── etc/cofiswarm/
    ├── var/lib/cofiswarm/
    ├── var/log/cofiswarm/
    └── run/cofiswarm/
```

### File map → `cofiswarm-deploy`

| cofiswarmdev | → deploy path |
|--------------|---------------|
| `production/docker-compose.prod.yml` | `compose/docker-compose.yml` (merge) |
| `production/Dockerfile` | `compose/Dockerfile.ui` |
| `production/nginx.conf` | `config/gateway/nginx.conf` |
| `production/install.sh` | `scripts/install-host.sh` (adapt paths) |
| `production/README.md` | `docs/production-notes.md` |
| `docker/pgvector/docker-compose.yml` | `compose/fragments/pgvector.yml` |
| `docker/Dockerfile.metal` | `compose/Dockerfile.metal` |
| `docker/Dockerfile.dev` | `compose/Dockerfile.dev` |
| `docker/Dockerfile.vllm-metal` | `compose/Dockerfile.vllm-metal` |
| `docker/docker-vllm-config.json` | `config/infer-vllm/vllm.json` |
| `scripts/matrix-env.sh` | `config/env/matrix-env.sh.example` |
| `scripts/matrix-env.local.sh` | **do not copy** (gitignored) |
| `scripts/deploy.sh` | `scripts/deploy.sh` |
| `scripts/rag-docker-compose.sh` | `scripts/rag-docker-compose.sh` |
| `scripts/cofiswarm-{1,2,3,r2}-*.sh` | `scripts/legacy/` (reference only) |
| `docs/MIGRATION-SPRINTS.md` | `docs/MIGRATION-SPRINTS.md` |
| `docs/REPO-STANDARD-LAYOUT.md` | `docs/REPO-STANDARD-LAYOUT.md` |
| `docs/ML-BOTTLENECKS.md` | `docs/ML-BOTTLENECKS.md` |
| `docs/sprints/` | `docs/sprints/` |
| `test/scripts/*.sh` | `test/scripts/` (full-stack variants) |

### 1b. Scaffold `cofiswarm-common`

| cofiswarmdev | → common path |
|--------------|---------------|
| `src/config/coordinatorSchema.js` | `schemas/coordinator.schema.json` (export) |
| `yyyyy/cpp_core/src/config/coordinator_config_validate*.cpp` | `spec/config-validation.md` + port to JSON Schema |
| `docs/BACKEND_ROUTING.md` | `spec/backend-routing.md` |
| `scripts/matrix-env.sh` | `env/MATRIX_HOSTS.md` (document every `MATRIX_*`) |
| — | `zmq/topics.yaml` (new) |
| — | `ports/well-known.yaml` (new, from REPO-STANDARD-LAYOUT §10) |

### 1c. Scaffold `cofiswarm-docs` (optional — or keep in deploy)

| cofiswarmdev | → docs repo |
|--------------|-------------|
| `docs/architecture-flow.md` | `architecture-flow.md` |
| `docs/CAPABILITIES.md` | `CAPABILITIES.md` |
| `docs/HELP.md` | `HELP.md` |
| `docs/APP_ANALYSIS.md` | `APP_ANALYSIS.md` |
| `docs/configuration.md` | `configuration.md` |
| `docs/model-management.md` | `model-management.md` |
| `README.md` | `README-monorepo-legacy.md` |

**Gate:** `deploy/test/scripts/assert-layout-full.sh` lists all roles from `repos.json`.

---

## Sprint 2 — `cofiswarm-config` + host `~/cofiswarm/fhs/etc`

**Goal:** Config source of truth on disk + in repo.

### Scaffold + map

| cofiswarmdev | → `cofiswarm-config` |
|--------------|----------------------|
| `config/agents/*.json` | `agents/*.json` |
| `config/coordinator.json` | `coordinator.json` |
| `config/system_cluster.yaml` | `system_cluster.yaml` |
| `swarm-config.template.json` | `templates/swarm-config.template.json` |
| `swarm-config.json` | `dist/swarm-config.json` (generated artifact) |
| `swarm-config-16gb.json` | `variants/16gb.json` |
| `swarm-config-32gb.json` | `variants/32gb.json` |
| `swarm-config-highquality.json` | `variants/highquality.json` |
| `swarm-config-8agents-text-image.json` | `variants/8agents-text-image.json` |
| `scripts/build_swarm_config.py` | `scripts/build_swarm_config.py` |
| `scripts/migrate_swarm_config.py` | `scripts/migrate_swarm_config.py` |
| `scripts/setup-config.sh` | `scripts/setup-config.sh` |
| `yyyyy/cpp_core/src/config/swarm_config_*.cpp` | `spec/swarm-config-resolve.md` (port later) |
| `yyyyy/cpp_core/src/config/coordinator_config_validate.*` | `scripts/validate.sh` (wrap) |
| `tools/swarmconfig-editor.html` | `tools/swarmconfig-editor.html` |
| `src/config/thresholds.js` | `schemas/thresholds.json` |

### Render to host FHS

```bash
cp -R ~/cofiswarm/repos/cofiswarm-config/agents ~/cofiswarm/fhs/etc/cofiswarm/config/
cp ~/cofiswarm/repos/cofiswarm-config/coordinator.json ~/cofiswarm/fhs/etc/cofiswarm/config/
python3 ~/cofiswarm/repos/cofiswarm-config/scripts/build_swarm_config.py \
  -o ~/cofiswarm/fhs/etc/cofiswarm/config/swarm-config.json
```

### `test/standalone`

| → `cofiswarm-config/test/standalone/etc/cofiswarm/config/` |
| Copy `agents/`, `coordinator.json`, built `swarm-config.json` |

**Gate:** `validate.sh` passes; host `~/cofiswarm/fhs/etc/cofiswarm/config/` populated.

---

## Sprint 3 — `cofiswarm-ui` + `cofiswarm-gateway` + `cofiswarm-stream-sdk`

### `cofiswarm-ui`

| cofiswarmdev | → ui path |
|--------------|-----------|
| `src/**` | `src/**` |
| `public/**` | `public/**` |
| `package.json`, `package-lock.json` | root |
| `production/Dockerfile` | `deploy/Dockerfile` |
| `scripts/ensure-react-scripts-patch.mjs` | `scripts/` |
| `scripts/postinstall.mjs` | `scripts/` |

### `cofiswarm-gateway`

| cofiswarmdev | → gateway path |
|--------------|----------------|
| `production/nginx.conf` | `deploy/nginx.conf` |
| `yyyyy/cpp_core/src/proxy_routes.cpp` | `spec/upstream-routes.md` (proxy → dispatch) |
| `yyyyy/cpp_core/src/proxy_routes_system.*` | `spec/system-routes.md` |

### `cofiswarm-stream-sdk`

| cofiswarmdev | → stream-sdk path |
|--------------|-------------------|
| `src/layouts/brewlate.streaming.test.js` | `fixtures/stream-expectations.js` |
| `docs/CAPABILITIES.md` (SSE section) | `spec/sse-events.md` |
| `yyyyy/cpp_core/src/coordinator_routes_architect_stream*.cpp` | `spec/sse-events.md` (extract event names) |
| — | `typescript/events.ts` (new from spec) |
| — | `go/events.go` (new) |

**Gate:** `npm test` in ui; `assert-layout.sh gateway` + `ui`.

---

## Sprint 4 — Bridge binaries: `coordinator`, `proxy`, `matrix-config`

Keep running during migration; thin copies first.

### `cofiswarm-coordinator`

| cofiswarmdev | → coordinator `src/` |
|--------------|----------------------|
| `yyyyy/cpp_core/src/coordinator.cpp` | `src/coordinator.cpp` |
| `yyyyy/cpp_core/src/coordinator_*.cpp` | `src/` (all coordinator_*) |
| `yyyyy/cpp_core/src/coordinator_*.h` | `src/` |
| `yyyyy/cpp_core/src/coordinator_routes*.cpp` | `src/routes/` |
| `yyyyy/cpp_core/src/coordinator_routes*.h` | `src/routes/` |
| `yyyyy/cpp_core/src/config/coordinator_config_validate.*` | `src/config/` |
| `scripts/yyyyy/build_cpp_binaries.sh` | `scripts/build.sh` |
| `yyyyy/_buildtmp/build_cpp_binaries.sh` | merge into `scripts/build.sh` |

**Exclude from coordinator (moved later):** see Sprint 6–8.

### `cofiswarm-proxy`

| cofiswarmdev | → proxy `src/` |
|--------------|----------------|
| `yyyyy/cpp_core/src/proxy.cpp` | `src/proxy.cpp` |
| `yyyyy/cpp_core/src/proxy_*.cpp` | `src/` |
| `yyyyy/cpp_core/src/proxy_*.h` | `src/` |

**Exclude from proxy (moved later):** `proxy_configure_spawn.cpp` → launcher; convert routes → convert.

### `cofiswarm-matrix-config`

| cofiswarmdev | → matrix-config |
|--------------|-----------------|
| `yyyyy/cpp_core/src/config_service_main.cpp` | `src/main.cpp` |
| `yyyyy/cpp_core/src/swarm_config_store.*` | `src/` |
| `yyyyy/cpp_core/src/swarm_config_roster.*` | `src/` |
| `yyyyy/cpp_core/src/config/swarm_config_dir_load.*` | `src/config/` |
| `yyyyy/cpp_core/src/config/path_expand.*` | `src/config/` |

**Gate:** `coordinator` + `proxy` build; read config from `~/cofiswarm/fhs/etc/cofiswarm/config/`.

---

## Sprint 5 — `infer-llama`, `infer-mlx`, `backend-*`

### `cofiswarm-infer-llama`

| cofiswarmdev | → infer-llama |
|--------------|---------------|
| `yyyyy/cpp_core/src/proxy_configure_spawn_args.h` | `deploy/entrypoint-args.sh` |
| `scripts/llama.sh` | `scripts/llama.sh` |
| `scripts/matrix-env.sh` (`MATRIX_LLAMA_SERVER`) | `configs/infer-llama.env.example` |
| — | `profiles/coder7b.env`, `llama8b.env`, … (from swarm-config groups) |
| `docker/Dockerfile.metal` | `deploy/Dockerfile` (optional) |

**Host models (symlink, do not copy weights):**

```bash
ln -sf /Users/Shared/llama/models ~/cofiswarm/fhs/var/lib/cofiswarm/models/llama
```

### `cofiswarm-infer-mlx`

| cofiswarmdev | → infer-mlx |
|--------------|-------------|
| `yyyyy/cpp_core/src/mlx_embed*.cpp` | `src/` (reference for HTTP server behavior) |
| `yyyyy/cpp_core/src/mlx_session_store.*` | `spec/session-bridge.md` → later dispatch |
| `yyyyy/cpp_core/src/model_registry_prompt_cache_codegen.cpp` | `src/` (if present) |
| `scripts/build_mlx_embed.sh` | `scripts/build.sh` |
| `scripts/mlx-conversion.sh` | `scripts/` |
| `orchestration/mlx_coordinator/backend.py` | `src/mlx_server/` |
| `docker/Dockerfile.metal` | `deploy/Dockerfile` |

### `cofiswarm-backend-sdk` + `backend-llama` + `backend-mlx`

| cofiswarmdev | → backend repos |
|--------------|-----------------|
| `backends/base.py` | `backend-sdk/src/cofiswarm_backend/` |
| `backends/__init__.py` | `backend-sdk/src/cofiswarm_backend/` |
| `yyyyy/cpp_core/src/inference_backend.*` | `backend-llama/spec/` (port contract) |
| `yyyyy/cpp_core/src/inference_backend_http.cpp` | `backend-llama/src/` |
| `yyyyy/cpp_core/src/agent_client_http.cpp` | `backend-llama/src/client.py` |
| `yyyyy/cpp_core/src/agent_stream_llama.h` | `backend-llama/spec/streaming.md` |
| `orchestration/mlx_coordinator/backend.py` | `backend-mlx/src/` |

**Gate:** `test/standalone/var/lib/cofiswarm/models/` has symlinks; profile env files exist per `server_group`.

---

## Sprint 6 — `slot-manager` + `kvpool` (extract from coordinator)

### `cofiswarm-slot-manager`

| cofiswarmdev | → slot-manager |
|--------------|----------------|
| `yyyyy/cpp_core/src/pressure_snapshot.cpp` | `internal/pressure/` |
| `yyyyy/cpp_core/src/pressure_snapshot_llama.cpp` | `internal/pressure/` |
| `yyyyy/cpp_core/src/pressure_snapshot_mlx.cpp` | `internal/pressure/` |
| `yyyyy/cpp_core/src/pressure_snapshot_llama_parse.h` | `internal/pressure/` |
| `yyyyy/cpp_core/src/pressure.h` | `internal/pressure/` |
| `yyyyy/cpp_core/src/coordinator_kv_ops.cpp` | `internal/kv/erase.go` (port) |
| `yyyyy/cpp_core/src/coordinator_kv_ops.h` | `internal/kv/` |
| `yyyyy/cpp_core/src/agent_client_pool.cpp` | `internal/concurrency/` (semaphores) |
| `yyyyy/cpp_core/src/agent_client_pool.h` | `internal/concurrency/` |
| `yyyyy/cpp_core/src/agent_client_pool_queue.h` | `internal/concurrency/` |
| `yyyyy/cpp_core/src/agent_health.*` | `internal/health/` (if exists) |
| `yyyyy/cpp_core/src/agent.h` | `spec/agent-endpoint.proto.json` |
| `docs/architecture-flow.md` | `docs/runbook.md` |

### `cofiswarm-kvpool`

| cofiswarmdev | → kvpool |
|--------------|----------|
| `yyyyy/cpp_core/src/kv_auto_clear.h` | `internal/policy/auto_clear.go` |
| `yyyyy/cpp_core/src/kv_importance_indexer.h` | `internal/policy/importance.go` |
| `yyyyy/cpp_core/src/prefix_cache.h` | `internal/policy/prefix.go` |
| `yyyyy/cpp_core/src/response_cache.*` | `internal/cache/` (or dispatch — decide) |
| `yyyyy/cpp_core/src/response_cache_evict.h` | `internal/cache/` |
| `yyyyy/cpp_core/src/token_budget_hierarchy.h` | `internal/budget/` |
| `yyyyy/cpp_core/src/token_ledger.*` | `internal/budget/` |
| `src/components/TokenBudgetGrid.js` | `spec/ui-contract.md` |

**Gate:** Port reads `COFISWARM_VAR_LIB`; pressure API returns same shape as `GET /api/pressure`.

---

## Sprint 7 — `agent-registry` + `launcher`

### `cofiswarm-agent-registry`

| cofiswarmdev | → agent-registry |
|--------------|------------------|
| `config/agents/*.json` | `data/agents/` (mirror; config remains SoT) |
| `yyyyy/cpp_core/src/agent.h` | `schemas/agent.json` |
| `yyyyy/cpp_core/src/swarm_config_roster.*` | `internal/roster/` |
| `yyyyy/cpp_core/src/coordinator_routes_agents_*.cpp` | `internal/http/` |
| `yyyyy/cpp_core/src/coordinator_routes_modes*.cpp` | `internal/modes/` (roster PUT) |
| `src/layouts/BrewConfigAgentsSection.js` | `spec/ui-fields.md` |

### `cofiswarm-launcher`

| cofiswarmdev | → launcher |
|--------------|------------|
| `yyyyy/cpp_core/src/proxy_configure.cpp` | `internal/configure/` (no spawn) |
| `yyyyy/cpp_core/src/proxy_configure_ports_*.cpp` | `internal/ports/` |
| `yyyyy/cpp_core/src/proxy_configure_health*.cpp` | `internal/health/` |
| `yyyyy/cpp_core/src/proxy_configure_kill_prepare.*` | `internal/lifecycle/` |
| `yyyyy/cpp_core/src/proxy_configure_spawn.cpp` | **reference only** → replace with Docker API |
| `bin/matrix.mjs` | `spec/launch-matrix.md` |
| `orchestration/lifecycle/launch.py` | `internal/legacy/launch.py` |
| `orchestration/lifecycle/full.py` | `internal/legacy/full.py` |
| `orchestration/lifecycle/shutdown.py` | `internal/shutdown.go` |
| `scripts/brewctl` | `scripts/brewctl` |

**Gate:** `launcher` starts compose profile `8gb` without `posix_spawn`.

---

## Sprint 8 — `dispatch` (extract orchestration shell)

### `cofiswarm-dispatch`

| cofiswarmdev | → dispatch |
|--------------|------------|
| `yyyyy/cpp_core/src/coordinator_routes_architect_stream*.cpp` | `src/stream/` |
| `yyyyy/cpp_core/src/coordinator_routes_dispatch*.cpp` | `src/dispatch/` |
| `yyyyy/cpp_core/src/coordinator_routes_architect_synthesis.*` | `src/synthesis/` |
| `yyyyy/cpp_core/src/synthesis_budget*.cpp` | `src/synthesis/` |
| `yyyyy/cpp_core/src/synthesis_tiered.*` | `src/synthesis/` |
| `yyyyy/cpp_core/src/session_store.*` | `src/session/` |
| `yyyyy/cpp_core/src/session_store_text.*` | `src/session/` |
| `yyyyy/cpp_core/src/session_store_context.h` | `src/session/` |
| `yyyyy/cpp_core/src/session_context.h` | `src/session/` |
| `yyyyy/cpp_core/src/session_compaction.h` | `src/session/` |
| `yyyyy/cpp_core/src/coordinator_routes_history_*.h` | `src/history/` |
| `yyyyy/cpp_core/src/coordinator_routes_history_search.h` | `src/history/` |
| `yyyyy/cpp_core/src/rag_client*.cpp` | `src/raginject/` |
| `yyyyy/cpp_core/src/rag_config.*` | `src/raginject/` |
| `yyyyy/cpp_core/src/rag_embed.*` | `src/raginject/` (coordinator-side embed) |
| `yyyyy/cpp_core/src/backend_router.*` | `src/routing/` |
| `yyyyy/cpp_core/src/inference_backend.*` | `src/clients/` (until backend-* pure) |
| `yyyyy/cpp_core/src/agent_client.*` | `src/clients/` |
| `yyyyy/cpp_core/src/agent_stream_llama.h` | `src/clients/` |
| `sessions.json` | `test/fixtures/sessions.json` → `var/lib/.../sessions/` |
| `history.json` | `test/fixtures/history.json` |

**Host state:**

```bash
mkdir -p ~/cofiswarm/fhs/var/lib/cofiswarm/dispatch/{sessions,history}
# optional seed from fixtures
```

**Gate:** SSE matches `stream-sdk/spec/sse-events.md`; sessions persist under `~/cofiswarm/fhs/var/lib/cofiswarm/dispatch/`.

---

## Sprint 9 — `mode-sdk` + four mode repos

### `cofiswarm-mode-sdk`

| cofiswarmdev | → mode-sdk |
|--------------|------------|
| `yyyyy/cpp_core/src/modes/mode.h` | `include/cofiswarm/mode.h` |
| `yyyyy/cpp_core/src/modes/registry.cpp` | `src/registry.cpp` |
| `yyyyy/cpp_core/src/mode_module.h` | `include/cofiswarm/mode_module.h` |
| `yyyyy/cpp_core/src/modes/README.md` | `README.md` |

### `cofiswarm-mode-flat`

| cofiswarmdev | → mode-flat `src/` |
|--------------|---------------------|
| `yyyyy/cpp_core/src/modes/flat.cpp` | `src/flat.cpp` |

### `cofiswarm-mode-pipeline`

| cofiswarmdev | → mode-pipeline `src/` |
|--------------|------------------------|
| `yyyyy/cpp_core/src/modes/pipeline.cpp` | `src/pipeline.cpp` |
| `yyyyy/cpp_core/src/modes/pipeline_*.cpp` | `src/` |
| `yyyyy/cpp_core/src/modes/pipeline_*.h` | `src/` |
| `yyyyy/cpp_core/src/coordinator_routes_architect_stream_pipeline.cpp` | `src/stream_bridge.cpp` |

### `cofiswarm-mode-cascade`

| cofiswarmdev | → mode-cascade `src/` |
|--------------|----------------------|
| `yyyyy/cpp_core/src/modes/cascade.cpp` | `src/cascade.cpp` |
| `yyyyy/cpp_core/src/modes/cascade_exec*.h` | `src/` |
| `yyyyy/cpp_core/src/coordinator_routes_architect_stream_modes.cpp` | `src/stream_bridge.cpp` (shared parts) |

### `cofiswarm-mode-router`

| cofiswarmdev | → mode-router `src/` |
|--------------|----------------------|
| `yyyyy/cpp_core/src/modes/router.cpp` | `src/router.cpp` |
| `yyyyy/cpp_core/src/modes/router_*.cpp` | `src/` |
| `yyyyy/cpp_core/src/modes/router_*.h` | `src/` |
| `yyyyy/cpp_core/src/coordinator_routes_architect_stream_router.cpp` | `src/stream_bridge.cpp` |

**Gate:** Each mode `test/standalone/etc/cofiswarm/mode-*/<role>.yaml` points at dispatch + slot-manager URLs.

---

## Sprint 10 — `orchestrate`, `rag`, `rag-worker`

### `cofiswarm-orchestrate`

| cofiswarmdev | → orchestrate |
|--------------|---------------|
| `orchestration/manager.py` | `src/cofiswarm_orchestrate/` |
| `orchestration/mlx_coordinator/service_orchestrate.py` | `src/` |
| `orchestration/mlx_coordinator/sidecar.py` | `src/` |
| `orchestration/lifecycle/check.py` | `src/lifecycle/` |
| `orchestration/telemetry/*` | `src/telemetry/` |
| `orchestration/requirements.txt` | `requirements.txt` |
| `yyyyy/cpp_core/src/proxy_routes_orchestrate.*` | `spec/proxy-routes.md` |

### `cofiswarm-rag`

| cofiswarmdev | → rag |
|--------------|-------|
| `orchestration/rag/service.py` | `src/cofiswarm_rag/` |
| `orchestration/rag/retrieve.py` | `src/` |
| `orchestration/rag/embed.py` | `src/` |
| `orchestration/rag/chunker.py` | `src/` |
| `orchestration/rag/store.py` | `src/` |
| `orchestration/rag/migrations/` | `migrations/` |
| `scripts/rag-ingest-server.py` | `scripts/ingest-server.py` |
| `yyyyy/cpp_core/src/coordinator_routes_rag_health.cpp` | `spec/health.md` |

### `cofiswarm-rag-worker`

| cofiswarmdev | → rag-worker |
|--------------|--------------|
| `orchestration/rag/service_jobs.py` | `src/jobs.py` |
| `orchestration/lifecycle/full.py` (auto-index spawn) | `src/auto_index.py` (no spawn) |
| `scripts/rag-docker-compose.sh` | `scripts/` |

**Host:**

```bash
mkdir -p ~/cofiswarm/fhs/var/lib/cofiswarm/rag/index
```

**Gate:** RAG reads `config/coordinator.json` rag block from FHS etc.

---

## Sprint 11 — `convert`, `observer`, `zmq-bridge`, `observer-sdk`

### `cofiswarm-convert`

| cofiswarmdev | → convert |
|--------------|-----------|
| `yyyyy/cpp_core/src/proxy_routes_convert*.cpp` | `src/` (port to job queue) |
| `scripts/gguf_to_mlx.py` | `src/gguf_to_mlx.py` |
| `scripts/convert-to-mlx.sh` | `scripts/` |
| `scripts/mlx-conversion.sh` | `scripts/` |

### `cofiswarm-observer` + `observer-sdk`

| cofiswarmdev | → observer |
|--------------|------------|
| `yyyyy/cpp_core/src/telemetry.*` | `internal/telemetry/` |
| `yyyyy/cpp_core/src/agent_metrics.*` | `plugins/metrics/` |
| `yyyyy/cpp_core/src/rss_generator.*` | `plugins/rss/` |
| `agent_logs/` (pattern) | `plugins/sink-agent-logs.yaml` |
| `orchestration/telemetry/logging.py` | `observer-sdk/examples/` |
| `logs/*.log` (structure) | `spec/log-format.md` |

### `cofiswarm-zmq-bridge`

| cofiswarmdev | → zmq-bridge |
|--------------|--------------|
| — (greenfield) | `internal/bus.go` |
| `docs/architecture-flow.md` | `spec/topics.md` (from common `zmq/topics.yaml`) |

**Host:**

```bash
mkdir -p ~/cofiswarm/fhs/var/lib/cofiswarm/observer/plugins
mkdir -p ~/cofiswarm/fhs/var/log/cofiswarm/agent_logs
```

---

## Sprint 12 — `e2e`, `models`, optional adapters

### `cofiswarm-e2e`

| cofiswarmdev | → e2e |
|--------------|-------|
| `test/scripts/*.sh` | `test/scripts/` |
| `docs/sprints/SCALE-GATES.md` | `test/gates/` |
| `src/chaos.test.js` | `test/ui-chaos/` |
| `yyyyy/tests/cpp/*` | `test/cpp-legacy/` |

### `cofiswarm-models` (optional)

| cofiswarmdev | → models |
|--------------|----------|
| `scripts/curl-model-download-36GB.sh` | `scripts/download/` |
| `scripts/cleanup-models.sh` | `scripts/` |
| `docs/model-management.md` | `catalog/README.md` |

### Deferred (Sprint 13+): `adapter-*`, `infer-vllm`, `tools`

| cofiswarmdev | → target |
|--------------|----------|
| `docker/Dockerfile.vllm-metal` | `infer-vllm` |
| `yyyyy/cpp_core/src/proxy_validate_vllm.*` | `infer-vllm` |
| `orchestration/modes/*.py` | `tools` or fold into orchestrate |

---

## Sprint 13 — Wire `~/cofiswarm/fhs` + compose on device

**Goal:** Full stack reads FHS paths; monorepo optional.

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
cp .env.example .env
# Edit: COFISWARM_FHS_ROOT=~/cofiswarm/fhs
make render-config
docker compose -f compose/docker-compose.yml \
  -f compose/profiles/16gb.yml up -d
```

| Host path | Service mount |
|-----------|---------------|
| `~/cofiswarm/fhs/etc/cofiswarm` | all services `:ro` |
| `~/cofiswarm/fhs/var/lib/cofiswarm` | dispatch, rag, slot-manager, models |
| `~/cofiswarm/fhs/var/log/cofiswarm` | infer, agent_logs |
| `~/cofiswarm/fhs/run/cofiswarm` | zmq-bridge |

**Gate:** SCALE-0 from [sprints/SCALE-0.md](./sprints/SCALE-0.md) completed against new layout.

---

## Sprint 14 — Cutover checklist

- [ ] Monorepo `bin/matrix.mjs` delegates to `cofiswarm-launcher`
- [ ] No writes to `cofiswarmdev/sessions.json` (only `~/cofiswarm/fhs/...`)
- [ ] `coordinator` + `proxy` bridge repos archived
- [ ] Tag monorepo `v3.0.0-bridge`; tag deploy `v1.0.0`
- [ ] `repos.json` pins compatible SHAs

---

## Master file map — shared C++ (agent client layer)

Used by **dispatch** until fully delegated to **backend-***:

| cofiswarmdev `yyyyy/cpp_core/src/` | Primary repo |
|-----------------------------------|--------------|
| `agent.h` | agent-registry (schema) + common |
| `agent_client.*` | dispatch |
| `agent_client_http.*` | backend-llama |
| `agent_stream_llama.h` | backend-llama |
| `agent_metrics.*` | observer |
| `utf8_sanitize.h` | common or dispatch |
| `host_memory.cpp` | slot-manager |
| `mlx_inflight.*` | infer-mlx + dispatch |
| `pressure.*` | slot-manager |

---

## Master file map — monorepo root misc

| cofiswarmdev | Target repo |
|--------------|-------------|
| `bin/matrix.mjs` | launcher |
| `bin/matrix-uninstall.mjs` | launcher/scripts |
| `bin/license.mjs` | **stay monorepo** or `cofiswarm-tools` |
| `package.json` | ui (split); root meta → deploy |
| `presets/` (if created) | config/presets/ |
| `licensing/` | **do not split** (proprietary) |
| `yyyyy/tests/` | e2e + per-repo `test/unit` |

---

## Scaffold command template (every sprint)

Run after creating each repo directory:

```bash
ROLE=dispatch   # change per repo
REPO=~/cofiswarm/repos/cofiswarm-${ROLE}
mkdir -p "${REPO}"/{configs,deploy/systemd,docs,scripts,test/{unit,integration,fixtures,scripts,standalone/{opt/cofiswarm/${ROLE},etc/cofiswarm/${ROLE},var/lib/cofiswarm/${ROLE},var/log/cofiswarm/${ROLE},run/cofiswarm}}}

# Copy test harness from monorepo
cp ~/cofiswarmdev/test/scripts/{env,assert-layout,init,reset}-standalone.sh \
   "${REPO}/test/scripts/" 2>/dev/null || true
cp ~/cofiswarmdev/test/scripts/env.sh "${REPO}/test/scripts/"
```

---

## Linear summary

| Sprint | Repos / dirs | Gate |
|--------|--------------|------|
| **0** | `~/cofiswarm/{repos,fhs}`, monorepo test | assert-layout |
| **1** | deploy, common, docs | repos.json + full test standalone |
| **2** | config → `fhs/etc` | validate.sh + build_swarm_config |
| **3** | ui, gateway, stream-sdk | npm test |
| **4** | coordinator, proxy, matrix-config | C++ build |
| **5** | infer-llama, infer-mlx, backend-* | model symlinks + profiles |
| **6** | slot-manager, kvpool | pressure API parity |
| **7** | agent-registry, launcher | compose up without spawn |
| **8** | dispatch | SSE + sessions on FHS |
| **9** | mode-sdk + 4 modes | mode yaml + healthz |
| **10** | orchestrate, rag, rag-worker | RAG index on FHS |
| **11** | convert, observer, zmq-bridge | plugins dir |
| **12** | e2e, models | SCALE-0 gates |
| **13** | fhs + compose wired | stack healthy |
| **14** | cutover | monorepo bridge only |

**Estimated calendar:** 2–3 sprints/week → **6–8 weeks** for structure + file copy on device; implementation/porting continues in parallel per repo.
