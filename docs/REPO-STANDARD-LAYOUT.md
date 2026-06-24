# Cofiswarm repo standard layout

Filesystem and naming conventions for every `keepdevops/cofiswarm-*` repository.
Aligned with **FHS**, **systemd**, **Docker**, and common Go/C++/Node packaging.

**Related:** master repo list in planning docs · [ML-BOTTLENECKS.md](./ML-BOTTLENECKS.md)

---

## 1. Global naming

| Item | Convention | Example |
|------|------------|---------|
| GitHub org | `keepdevops` | `github.com/keepdevops/cofiswarm-dispatch` |
| Repo name | `cofiswarm-<role>` kebab-case | `cofiswarm-slot-manager` |
| Binary / image | same as repo short name | `cofiswarm-dispatch` |
| Docker image | `ghcr.io/keepdevops/cofiswarm-dispatch:<tag>` | tag = git sha or semver |
| systemd unit | `cofiswarm-<role>.service` | `cofiswarm-dispatch.service` |
| Config basename | `<role>.yaml` or `<role>.json` | `dispatch.yaml` |
| Env prefix | `COFISWARM_<ROLE>_` or shared `MATRIX_*` (legacy) | `COFISWARM_DISPATCH_HOST` |
| ZMQ topic prefix | `swarm.<domain>.` | `swarm.kvpool.evict` |
| Log identifier | `cofiswarm-<role>` | journald / Loki label |

**Legacy:** `MATRIX_*` env vars remain supported during monolith migration; new
services prefer `COFISWARM_*` with `MATRIX_*` aliases documented in `common`.

---

## 2. Host layout (standalone / bare metal / VM)

FHS-aligned install root for production outside Docker:

```
/opt/cofiswarm/                          # application trees (read-only payloads)
├── bin/                                 # wrapper scripts → /opt/cofiswarm/<svc>/bin
├── dispatch/
│   └── current -> releases/1.2.3/       # symlink deploy pattern
├── slot-manager/
├── kvpool/
├── infer-llama/
└── …

/etc/cofiswarm/                          # configuration (config management target)
├── dispatch/
│   ├── dispatch.yaml                    # main config
│   ├── dispatch.env                     # EnvironmentFile for systemd
│   └── conf.d/                          # drop-in fragments
├── slot-manager/
├── kvpool/
├── agent-registry/
├── config/                              # swarm / coordinator (source of truth)
│   ├── swarm-config.json
│   ├── coordinator.json
│   └── agents/
└── profiles/                            # 8gb | 16gb | 32gb | scale-N

/var/lib/cofiswarm/                      # mutable state
├── dispatch/
│   ├── sessions/
│   └── history/
├── slot-manager/
│   └── registry.db                      # optional sqlite
├── kvpool/
├── rag/
│   └── index/
├── observer/
│   └── plugins/
└── models/                              # GGUF / MLX weights (or symlink to /mnt/models)
    ├── llama/
    └── mlx/

/var/log/cofiswarm/                      # logs (if not journald-only)
├── dispatch/
├── infer-llama/
└── agent_logs/                          # legacy name; prefer per-endpoint subdirs

/run/cofiswarm/                          # pid sockets, runtime (tmpfs)
├── dispatch.sock
└── zmq/

/usr/local/lib/systemd/system/           # or /etc/systemd/system/
├── cofiswarm-dispatch.service
├── cofiswarm-slot-manager.service
└── cofiswarm.target                     # wants all cofiswarm-*.service
```

### systemd unit template

```ini
# /etc/systemd/system/cofiswarm-dispatch.service
[Unit]
Description=Cofiswarm dispatch (SSE, sessions, mode router)
After=network-online.target cofiswarm-slot-manager.service
Wants=cofiswarm-slot-manager.service
PartOf=cofiswarm.target

[Service]
Type=simple
User=cofiswarm
Group=cofiswarm
EnvironmentFile=-/etc/cofiswarm/dispatch/dispatch.env
ExecStart=/opt/cofiswarm/dispatch/current/bin/cofiswarm-dispatch \
          --config /etc/cofiswarm/dispatch/dispatch.yaml
StateDirectory=cofiswarm/dispatch
LogsDirectory=cofiswarm/dispatch
Restart=on-failure
RestartSec=5
NoNewPrivileges=true

[Install]
WantedBy=cofiswarm.target
```

`StateDirectory=` creates `/var/lib/cofiswarm/dispatch` on modern systemd.

---

## 3. Container layout (every runtime image)

Same logical paths **inside** the container:

```
/app/                                    # WORKDIR; read-only root except volumes
├── bin/<binary>                         # ENTRYPOINT
├── lib/                                 # shared libs if any
└── share/
    └── doc/                             # LICENSE, README snippet

/etc/cofiswarm/<role>/                 # mounted or baked defaults
└── <role>.yaml

/var/lib/cofiswarm/<role>/             # volume mount
/var/log/cofiswarm/<role>/             # volume or stdout → collector
/tmp/                                    # ephemeral only
```

**Dockerfile conventions:**

```dockerfile
FROM gcr.io/distroless/static-debian12   # Go services
# or FROM ubuntu:24.04 / python:3.12-slim / node:22-bookworm-slim

LABEL org.opencontainers.image.source=https://github.com/keepdevops/cofiswarm-dispatch
LABEL org.opencontainers.image.title=cofiswarm-dispatch

RUN groupadd -r cofiswarm && useradd -r -g cofiswarm cofiswarm
COPY --chown=cofiswarm:cofiswarm bin/cofiswarm-dispatch /app/bin/
USER cofiswarm
WORKDIR /app
ENTRYPOINT ["/app/bin/cofiswarm-dispatch"]
CMD ["--config", "/etc/cofiswarm/dispatch/dispatch.yaml"]
```

---

## 4. Docker Compose / deploy repo layout

`cofiswarm-deploy` is the **only** place full stack topology lives:

```
cofiswarm-deploy/
├── README.md
├── repos.json
├── Makefile
├── .env.example
├── compose/
│   ├── docker-compose.yml               # base
│   ├── docker-compose.override.yml      # local dev
│   ├── profiles/
│   │   ├── 8gb.yml
│   │   ├── 16gb.yml
│   │   ├── 32gb.yml
│   │   └── scale-sprint-N.yml
│   └── test.integration.yml             # e2e
├── config/                              # rendered → container /etc/cofiswarm
│   └── …
├── grafana/
│   ├── dashboards/
│   └── provisioning/
├── systemd/                             # optional bare-metal install
│   ├── cofiswarm.target
│   └── cofiswarm-*.service
├── scripts/
│   ├── install-host.sh                  # /opt + /etc + user
│   ├── render-config.sh
│   └── backup-state.sh                  # /var/lib/cofiswarm
└── docs/
    ├── MIGRATION.md
    └── DEPRECATIONS.md
```

**Compose volume mapping (standard):**

```yaml
volumes:
  cofiswarm-dispatch-state:
    driver: local
services:
  dispatch:
    volumes:
      - cofiswarm-dispatch-state:/var/lib/cofiswarm/dispatch
      - ./config/dispatch:/etc/cofiswarm/dispatch:ro
```

---

## 5. Source repository layout (all repos)

### 5.1 Common skeleton (every repo)

```
cofiswarm-<role>/
├── README.md
├── LICENSE
├── CHANGELOG.md
├── Makefile                             # build, test, image, lint
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── release.yml
├── docs/
│   ├── README.md                        # operator notes
│   └── runbook.md
├── configs/                             # examples → installed to /etc/cofiswarm/<role>/
│   ├── <role>.yaml.example
│   └── <role>.env.example
├── deploy/
│   ├── Dockerfile
│   ├── docker-compose.fragment.yml      # snippet for cofiswarm-deploy
│   └── systemd/
│       └── cofiswarm-<role>.service
├── scripts/
│   ├── build.sh
│   └── install.sh                       # optional host install to /opt/cofiswarm
└── test/                                # required — see §15
```

### 5.2 Go control-plane service

Applies to: `launcher`, `slot-manager`, `kvpool`, `observer`, `zmq-bridge`,
`dispatch`, `e2e` (test harness).

```
├── cmd/
│   └── cofiswarm-<role>/
│       └── main.go
├── internal/
│   ├── config/
│   ├── http/                            # handlers
│   ├── zmq/
│   └── <domain>/
├── pkg/                                 # only if imported by other repos
│   └── api/
├── api/
│   └── openapi.yaml
├── go.mod
├── go.sum
└── test/
    ├── unit/
    ├── integration/
    └── standalone/                      # §15 — mirrors FHS for this role
```

### 5.3 C++ service / infer image

Applies to: `infer-llama`, `infer-mlx`, `coordinator` (bridge), `proxy` (bridge).

```
├── cmake/
├── include/cofiswarm/<role>/
├── src/
├── third_party/                         # vendored if needed
├── configs/
├── deploy/Dockerfile                    # installs llama-server or mlx entrypoint
└── test/
    ├── unit/
    ├── integration/
    └── standalone/
```

### 5.4 Python sidecar / backend

Applies to: `orchestrate`, `rag`, `rag-worker`, `convert`, `backend-*`,
`adapter-*`.

```
├── src/cofiswarm_<role>/               # or backends/<name>/
│   └── __init__.py
├── pyproject.toml
├── requirements.txt                     # or uv.lock
├── configs/
└── test/
    ├── unit/
    ├── integration/
    └── standalone/
```

### 5.5 Node / React UI

Applies to: `ui`, `stream-sdk` (typescript package).

```
├── public/
├── src/
├── package.json
├── configs/
├── deploy/
│   ├── Dockerfile                       # nginx static or node serve
│   └── nginx.conf                       # ui only
└── test/
    ├── unit/
    ├── integration/
    └── standalone/
```

### 5.6 SDK / contract-only repo

Applies to: `common`, `stream-sdk`, `mode-sdk`, `observer-sdk`, `backend-sdk`.

```
├── spec/                                # human-readable contract
│   ├── README.md
│   └── *.md | *.yaml
├── go/                                  # optional
├── typescript/
├── fixtures/
├── schemas/                             # JSON Schema
├── package.json | go.mod
└── test/
    ├── unit/                            # schema validation tests
    └── standalone/
        └── etc/cofiswarm/               # fixture configs only
```

### 5.7 Config / registry data repo

Applies to: `config`, `agent-registry` (if split).

```
├── agents/                              # one file per agent
├── variants/
│   ├── 8gb.json
│   ├── 16gb.json
│   └── 32gb.json
├── schemas/
├── scripts/
│   ├── build_swarm_config.py
│   └── validate.sh
├── dist/                                # generated swarm-config.json (CI artifact)
└── test/
    ├── unit/
    └── standalone/
        └── etc/cofiswarm/config/        # mirrors production config tree
```

---

## 6. Per-repo directory map

| Repo | Source type | `cmd/` or entry | State under `/var/lib/cofiswarm/` |
|------|-------------|-----------------|-----------------------------------|
| `deploy` | meta | scripts | — (orchestrates volumes) |
| `gateway` | nginx | — | — |
| `ui` | node | `src/` | — |
| `config` | data | scripts | — |
| `agent-registry` | go/json | `cmd/` | `agent-registry/` |
| `launcher` | go | `cmd/cofiswarm-launcher` | `launcher/` |
| `slot-manager` | go | `cmd/cofiswarm-slot-manager` | `slot-manager/` |
| `kvpool` | go | `cmd/cofiswarm-kvpool` | `kvpool/` |
| `observer` | go | `cmd/cofiswarm-observer` | `observer/plugins/` |
| `zmq-bridge` | go | `cmd/cofiswarm-zmq-bridge` | — |
| `dispatch` | go/cpp | `cmd/` | `dispatch/sessions`, `history` |
| `mode-sdk` | cpp/lib | cmake | — |
| `mode-flat` | go/cpp | `cmd/` | — |
| `mode-pipeline` | go/cpp | `cmd/` | — |
| `mode-cascade` | go/cpp | `cmd/` | — |
| `mode-router` | go/cpp | `cmd/` | — |
| `common` | schemas | — | — |
| `stream-sdk` | spec | — | — |
| `e2e` | shell/go | `test/` | — |
| `coordinator` | cpp | `src/coordinator.cpp` | legacy |
| `proxy` | cpp | `src/proxy.cpp` | legacy |
| `infer-llama` | cpp/wrap | llama-server | — |
| `infer-mlx` | python | mlx entry | `infer-mlx/cache/` |
| `infer-vllm` | docker | vllm serve | — |
| `infer-sglang` | docker | sglang | — |
| `infer-ollama` | docker | ollama | — |
| `backend-sdk` | py | `src/` | — |
| `backend-llama` | py | `src/` | — |
| `backend-mlx` | py | `src/` | — |
| `backend-vllm` | py | `src/` | — |
| `adapter-openai-compat` | go/py | `cmd/` | — |
| `adapter-agentic` | go/py | `cmd/` | — |
| `orchestrate` | py | `src/` | `orchestrate/` |
| `rag` | py | `src/` | `rag/index/` |
| `rag-worker` | py | `src/` | `rag/work/` |
| `convert` | py/cpp | `src/` | `convert/jobs/` |
| `tools` | py | `src/` | — |
| `matrix-config` | cpp | binary | — |
| `observer-sdk` | spec | — | — |
| `models` | scripts | `scripts/` | host: `/var/lib/cofiswarm/models` |
| `grafana` | json | `dashboards/` | — |
| `pgvector` | docker | compose fragment | `pgvector/data/` | _(archived — RAG is serverless sqlite-vec now)_ |
| `docs` | md | — | — |

---

## 7. Mode service standard (`cofiswarm-mode-*`)

All four mode repos share identical layout:

```
cofiswarm-mode-flat/
├── cmd/cofiswarm-mode-flat/main.go      # or cpp binary
├── internal/mode/
│   ├── run.go                           # implements mode-sdk contract
│   └── stream.go
├── configs/mode-flat.yaml
├── deploy/
│   ├── Dockerfile
│   └── docker-compose.fragment.yml
└── test/
    ├── unit/
    ├── integration/
    └── standalone/                      # full FHS mirror for mode-flat
```

**Config (`/etc/cofiswarm/mode-flat/mode-flat.yaml`):**

```yaml
listen: ":8021"
dispatch_url: "http://cofiswarm-dispatch:8010"
agent_registry_url: "http://cofiswarm-agent-registry:8012"
slot_manager_url: "http://cofiswarm-slot-manager:8013"
zmq_pub: "tcp://cofiswarm-zmq-bridge:5556"
```

---

## 8. Infer image standard (`cofiswarm-infer-*`)

```
cofiswarm-infer-llama/
├── deploy/
│   ├── Dockerfile
│   ├── entrypoint.sh                    # exec llama-server with env
│   └── docker-compose.fragment.yml
├── configs/
│   └── infer-llama.env.example
├── profiles/
│   ├── coder7b.env                      # MODEL_PATH, PARALLEL, CTX_CAP
│   └── llama8b.env
├── docs/
│   └── runbook.md
└── test/
    ├── unit/
    ├── integration/
    └── standalone/
        ├── etc/cofiswarm/infer-llama/
        └── var/lib/cofiswarm/models/llama/   # tiny fixture gguf or stub
```

**Runtime env (compose):**

```bash
COFISWARM_INFER_ENDPOINT_ID=coder7b
COFISWARM_INFER_MODEL_PATH=/var/lib/cofiswarm/models/llama/qwen7b.gguf
COFISWARM_INFER_PARALLEL=4
COFISWARM_INFER_CTX_CAP=6144
COFISWARM_INFER_CACHE_TYPE_K=q4_0
COFISWARM_INFER_CACHE_TYPE_V=q8_0
```

**No source in infer repo** if image only wraps upstream `llama-server` — then
tree is `deploy/` + `configs/profiles/` + `docs/` only.

---

## 9. Observer plugin layout

Host:

```
/var/lib/cofiswarm/observer/plugins/
├── kv-trace.yaml
├── opencode-trace.yaml
└── agent-logs-sink.yaml
```

Repo `cofiswarm-observer-sdk`:

```
observer-sdk/
├── spec/plugin.schema.yaml
├── examples/
│   ├── sink-agent-logs.yaml
│   └── filter-kv-only.yaml
└── typescript/                          # optional UI for plugin editor
```

---

## 10. Network ports (well-known)

Allocate in `cofiswarm-common` — avoid collision with legacy localhost ports.

| Service | Internal port | Legacy |
|---------|---------------|--------|
| gateway | 3002 | proxy |
| ui | 3000 | ui |
| dispatch | 8010 | coordinator 8000 |
| slot-manager | 8013 | — |
| kvpool | 8014 | — |
| agent-registry | 8012 | — |
| config API | 8011 | matrix_config 8011 |
| orchestrate | 3003 | same |
| rag | 8001 | same |
| mode-flat | 8021 | — |
| mode-pipeline | 8022 | — |
| mode-cascade | 8023 | — |
| mode-router | 8024 | — |
| zmq control | 5555 | — |
| zmq pub | 5556 | — |
| infer (per service) | 8080 | 8083–8089 legacy |

Infer containers **always listen on 8080 internally**; legacy host ports
8083–8089 exist only in dev `compose.override.yml`.

---

## 11. New standalone directories to create on host

One-time provisioning (`cofiswarm-deploy/scripts/install-host.sh`):

```bash
install -d -o cofiswarm -g cofiswarm -m 0750 \
  /opt/cofiswarm \
  /etc/cofiswarm/{dispatch,slot-manager,kvpool,config,profiles} \
  /var/lib/cofiswarm/{dispatch,slot-manager,kvpool,rag,observer,models/{llama,mlx}} \
  /var/log/cofiswarm \
  /run/cofiswarm
```

**User:** system user `cofiswarm` (no login shell, `/usr/sbin/nologin`).

---

## 12. Monorepo → multi-repo path mapping (migration)

| Monorepo today | Target repo | Target path |
|----------------|-------------|-------------|
| `src/` | `cofiswarm-ui` | `src/` |
| `config/agents/` | `cofiswarm-config` | `agents/` |
| `swarm-config.json` | `cofiswarm-config` | `dist/swarm-config.json` |
| `yyyyy/cpp_core/src/modes/` | `cofiswarm-mode-*` + `mode-sdk` | `src/` / `internal/mode/` |
| `yyyyy/cpp_core/src/coordinator*` | `dispatch` + bridge `coordinator` | `internal/` |
| `yyyyy/cpp_core/src/proxy*` | `gateway` + `launcher` + bridge `proxy` | — |
| `yyyyy/cpp_core/src/*kv*` | `kvpool` + `slot-manager` | `internal/` |
| `orchestration/` | `orchestrate` | `src/cofiswarm_orchestrate/` |
| `backends/` | `backend-*` | `src/` |
| `production/` | `deploy` | `compose/` |
| `docs/` | `docs` or `deploy/docs` | — |
| `agent_logs/` | host | `/var/log/cofiswarm/agent_logs/` |
| `sessions.json`, `history.json` | host | `/var/lib/cofiswarm/dispatch/` |

---

## 13. Checklist for new repo bootstrap

- [ ] `README.md` with role, ports, env vars, FHS paths
- [ ] `configs/<role>.yaml.example` → `/etc/cofiswarm/<role>/`
- [ ] `deploy/Dockerfile` + `docker-compose.fragment.yml`
- [ ] `deploy/systemd/cofiswarm-<role>.service`
- [ ] `test/standalone/` — full FHS mirror for this role (§15)
- [ ] `test/scripts/{init,reset,assert-layout}.sh`
- [ ] `Makefile` targets: `build`, `test`, `test-standalone`, `image`, `lint`
- [ ] `.github/workflows/ci.yml` runs `make test` + `make test-standalone`
- [ ] Register in `cofiswarm-deploy/repos.json`
- [ ] Document state dir under `/var/lib/cofiswarm/<role>/`
- [ ] Non-root `cofiswarm` user in image
- [ ] Health: `GET /healthz` or `GET /readyz`

---

## 14. Quick reference — four views

| View | Root | Config | State | Logs |
|------|------|--------|-------|------|
| **Host FHS** | `/opt/cofiswarm/<role>` | `/etc/cofiswarm/<role>` | `/var/lib/cofiswarm/<role>` | `/var/log/cofiswarm/<role>` |
| **Container** | `/app` | `/etc/cofiswarm/<role>` | `/var/lib/cofiswarm/<role>` | stdout → observer |
| **Git repo** | `cmd/` `src/` | `configs/*.example` | — (stateless image) | — |
| **Git test** | `test/standalone/opt/...` | `test/standalone/etc/...` | `test/standalone/var/lib/...` | `test/standalone/var/log/...` |

All cofiswarm repos should be **stateless images + mounted `/var/lib`**, config
in **`/etc/cofiswarm`**, binaries in **`/app/bin`** or **`/opt/cofiswarm`**.

---

## 15. Test directory — mirror every standalone FHS path

Every repo **must** include `test/standalone/`, a miniature copy of the five
production FHS roots. Tests never write to real `/opt`, `/etc`, `/var`, or
`/run` on the host.

### 15.1 Rule

| Production path | Test mirror (in repo) |
|-----------------|------------------------|
| `/opt/cofiswarm/<role>/` | `test/standalone/opt/cofiswarm/<role>/` |
| `/etc/cofiswarm/<role>/` | `test/standalone/etc/cofiswarm/<role>/` |
| `/var/lib/cofiswarm/<role>/` | `test/standalone/var/lib/cofiswarm/<role>/` |
| `/var/log/cofiswarm/<role>/` | `test/standalone/var/log/cofiswarm/<role>/` |
| `/run/cofiswarm/` | `test/standalone/run/cofiswarm/` |

**Shared paths** (config, models, profiles) use the same prefix:

| Production | Test mirror |
|------------|-------------|
| `/etc/cofiswarm/config/` | `test/standalone/etc/cofiswarm/config/` |
| `/etc/cofiswarm/profiles/` | `test/standalone/etc/cofiswarm/profiles/` |
| `/var/lib/cofiswarm/models/` | `test/standalone/var/lib/cofiswarm/models/` |

### 15.2 Standard `test/` layout (every repo)

```
test/
├── README.md                            # how to run; env vars
├── unit/                                # no filesystem; mocks only
├── integration/                         # may call test-standalone root
├── standalone/                          # committed skeleton + gitignored runtime
│   ├── opt/cofiswarm/<role>/
│   │   └── bin/                         # populated by `make build` in CI
│   ├── etc/cofiswarm/<role>/
│   │   ├── <role>.yaml                  # from configs/*.example
│   │   └── <role>.env
│   ├── var/lib/cofiswarm/<role>/        # fixture state; .gitkeep
│   ├── var/log/cofiswarm/<role>/        # .gitkeep
│   └── run/cofiswarm/                   # .gitkeep; ephemeral in CI
├── fixtures/                            # golden JSON/SSE; copied into standalone
│   ├── sessions.json
│   └── pressure-snapshot.json
└── scripts/
    ├── init-standalone.sh               # mkdir, copy fixtures, build binary
    ├── reset-standalone.sh              # wipe var/lib, var/log, run
    └── assert-layout.sh                 # fail CI if FHS tree incomplete
```

### 15.3 Environment — point services at test root

```bash
# test/scripts/env.sh (sourced by init-standalone.sh and integration tests)
export COFISWARM_TEST_ROOT="$(cd "$(dirname "$0")/../standalone" && pwd)"
export COFISWARM_OPT_ROOT="${COFISWARM_TEST_ROOT}/opt/cofiswarm"
export COFISWARM_ETC_ROOT="${COFISWARM_TEST_ROOT}/etc/cofiswarm"
export COFISWARM_VAR_LIB="${COFISWARM_TEST_ROOT}/var/lib/cofiswarm"
export COFISWARM_VAR_LOG="${COFISWARM_TEST_ROOT}/var/log/cofiswarm"
export COFISWARM_RUN_ROOT="${COFISWARM_TEST_ROOT}/run/cofiswarm"

# Service under test (example: dispatch)
export COFISWARM_DISPATCH_CONFIG="${COFISWARM_ETC_ROOT}/dispatch/dispatch.yaml"
export COFISWARM_DISPATCH_STATE="${COFISWARM_VAR_LIB}/dispatch"
export COFISWARM_DISPATCH_LOG="${COFISWARM_VAR_LOG}/dispatch"
```

Services accept overrides:

```yaml
# configs/dispatch.yaml.example
paths:
  config: /etc/cofiswarm/dispatch
  state: /var/lib/cofiswarm/dispatch
  log: /var/log/cofiswarm/dispatch
```

Tests pass the `COFISWARM_*_ROOT` equivalents via flags or env.

### 15.4 `assert-layout.sh` (required in every repo)

Validates the five standalone roots exist for `<role>`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROLE="${1:?usage: assert-layout.sh <role>}"
ROOT="$(cd "$(dirname "$0")/../standalone" && pwd)"
for base in opt etc var/lib var/log run; do
  case "$base" in
    opt)    dir="${ROOT}/opt/cofiswarm/${ROLE}" ;;
    etc)    dir="${ROOT}/etc/cofiswarm/${ROLE}" ;;
    var/lib) dir="${ROOT}/var/lib/cofiswarm/${ROLE}" ;;
    var/log) dir="${ROOT}/var/log/cofiswarm/${ROLE}" ;;
    run)    dir="${ROOT}/run/cofiswarm" ;;
  esac
  [[ -d "$dir" ]] || { echo "missing: $dir"; exit 1; }
done
echo "ok: standalone layout for ${ROLE}"
```

### 15.5 Makefile targets

```makefile
test: test-unit test-standalone-layout
test-unit:
	go test ./...    # or pytest, npm test, ctest

test-standalone-layout:
	./test/scripts/assert-layout.sh $(ROLE)

test-standalone: test-standalone-layout
	./test/scripts/init-standalone.sh
	go test -tags=integration ./test/integration/...
	./test/scripts/reset-standalone.sh
```

### 15.6 `.gitignore` (per repo)

```
test/standalone/opt/cofiswarm/*/bin/*
!test/standalone/opt/cofiswarm/*/bin/.gitkeep
test/standalone/var/lib/**/*
!test/standalone/var/lib/**/.gitkeep
test/standalone/var/log/**/*
!test/standalone/var/log/**/.gitkeep
test/standalone/run/**/*
!test/standalone/run/**/.gitkeep
```

Commit: **directory skeleton**, **fixture configs**, **`.gitkeep`**.  
Ignore: **runtime state**, **built binaries**, **test logs**.

### 15.7 Per-role `test/standalone` minimum

| Repo | `etc/cofiswarm/<role>/` | `var/lib/cofiswarm/<role>/` fixtures |
|------|-------------------------|--------------------------------------|
| `dispatch` | `dispatch.yaml` | `sessions/`, `history/` sample JSON |
| `slot-manager` | `slot-manager.yaml` | `endpoints.json` |
| `kvpool` | `kvpool.yaml` | empty or policy snapshot |
| `agent-registry` | `agent-registry.yaml` | `agents/` dir mirroring config |
| `config` | N/A — use `etc/cofiswarm/config/` | `agents/*.json` |
| `infer-llama` | `infer-llama.env` | stub model path under `models/llama/` |
| `infer-mlx` | `infer-mlx.yaml` | `cache/` |
| `rag` | `rag.yaml` | `index/` minimal |
| `observer` | `observer.yaml` | `plugins/*.yaml` |
| `ui` | `ui.env` | — |
| `gateway` | `nginx.conf` fragment | — |

### 15.8 `cofiswarm-deploy` — full-stack test standalone

Deploy owns the **union** of all service mirrors for e2e:

```
cofiswarm-deploy/test/
├── standalone/                          # full stack FHS mirror
│   ├── opt/cofiswarm/                   # all roles
│   ├── etc/cofiswarm/                   # all roles + config + profiles
│   ├── var/lib/cofiswarm/               # all state dirs
│   ├── var/log/cofiswarm/
│   └── run/cofiswarm/
├── fixtures/
│   └── profile-8gb/                     # full etc + config snapshot
├── integration/
│   └── compose-test.sh
└── scripts/
    ├── init-standalone-full.sh
    ├── reset-standalone-full.sh
    └── assert-layout-full.sh            # every role from repos.json
```

`cofiswarm-e2e` imports this tree or clones deploy’s `test/standalone` via
submodule / CI artifact.

### 15.9 `cofiswarm-e2e` layout

```
cofiswarm-e2e/
├── test/
│   ├── standalone/                      # symlink or copy from deploy in CI
│   ├── integration/
│   │   ├── mode_smoke.sh
│   │   └── kv_pressure_gate.sh
│   └── scripts/
│       └── env.sh                       # COFISWARM_TEST_ROOT → deploy mirror
└── Makefile
```

### 15.10 CI order

1. `assert-layout.sh` — tree exists  
2. `init-standalone.sh` — copy fixtures, build binary into `test/standalone/opt/...`  
3. `unit` — fast  
4. `integration` — service reads `COFISWARM_TEST_ROOT`  
5. `reset-standalone.sh` — clean mutable dirs  
6. (deploy only) `compose -f compose/test.integration.yml up --abort-on-container-exit`

### 15.11 Monorepo interim (cofiswarmdev)

Until repos split, mirror under repo root:

```
test/standalone/
├── opt/cofiswarm/
├── etc/cofiswarm/
├── var/lib/cofiswarm/
├── var/log/cofiswarm/
└── run/cofiswarm/
```

Legacy files map into test fixtures:

| Legacy | Test fixture path |
|--------|-------------------|
| `sessions.json` | `test/standalone/var/lib/cofiswarm/dispatch/sessions/sessions.json` |
| `history.json` | `test/standalone/var/lib/cofiswarm/dispatch/history/history.json` |
| `config/agents/` | `test/standalone/etc/cofiswarm/config/agents/` |
| `swarm-config.json` | `test/standalone/etc/cofiswarm/config/swarm-config.json` |
| `agent_logs/` | `test/standalone/var/log/cofiswarm/agent_logs/` |
