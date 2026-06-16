# Production deployment (UI)

Cofiswarm keeps **inference on the host** (Metal / GPU): `llama-server`, MLX servers, and **dispatch** on port **8010**. The **React UI** runs in Docker on **:3000** and proxies `/api/*` → dispatch.

## Quick start (post-migration)

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
make ui-build && make up
open http://127.0.0.1:3000
make test-ui-ops-gate
```

Legacy **proxy :3002** (`cofiswarm-gateway`) is archived — use UI nginx on :3000 instead.

## 1. Host: proxy + API

Set paths once (prints suggested defaults for your OS):

```bash
source scripts/matrix-env.sh          # or: eval "$(bash scripts/matrix-env.sh)"
bash scripts/matrix-validate-env.sh   # optional checks
```

From the repo root (after `bash production/install.sh` or `bash scripts/install.sh` and builds as needed):

```bash
./proxy >> logs/proxy.log 2>&1 &
# Configure models from the UI as usual (CONFIGURE → LAUNCH SWARM starts coordinator + servers).
```

`scripts/launch_matrix.sh` **sources** `scripts/matrix-env.sh` automatically so child processes inherit `MATRIX_*`.

## 2. Container: static UI + `/api` → host

Build the UI with the API base set to **`/api`** (nginx forwards `/api` to `host.docker.internal:3002`). Run these from the **repository root**:

```bash
docker compose -f production/docker-compose.prod.yml build --no-cache
docker compose -f production/docker-compose.prod.yml up -d
```

Open **http://localhost** (port 80). The browser calls **`/api/*`**, nginx proxies to the host proxy.

**Linux:** ensure `extra_hosts: host.docker.internal:host-gateway` (already in `production/docker-compose.prod.yml` for Docker 20.10+).

## 3. Environment

| Variable | Where | Purpose |
|----------|--------|---------|
| `REACT_APP_API_BASE` | **Build time** (CRA) | `/api` for same-origin via UI nginx → dispatch :8010 |
| `MATRIX_LAUNCH_MODE` | **Runtime** (shell) | `1` = Docker UI, `2` = bare metal (`scripts/launch_matrix.sh`) |
| `MATRIX_MODEL_DIR` | **Runtime** (proxy) | Directory containing `.gguf` files and MLX model folders |
| `MATRIX_LLAMA_SERVER` | **Runtime** | Path to `llama-server` binary |
| `MATRIX_ACTIVE_CONFIG` | **Runtime** | Active config (default `/tmp/matrix-active-config.json`) |
| `MATRIX_SLOTS_DIR` | **Runtime** | llama-server `--slot-save-path` (default `/tmp/matrix-slots`) |
| `MATRIX_MLX_PYTHON` | **Runtime** | Python for `mlx_lm.server` (defaults to pixi mlx env or `python3`) |
| `MATRIX_PROXY_PORT` | **Runtime** | Legacy proxy port (**3002**, archived). Use `make up` + UI :3000. |
| `MATRIX_COORDINATOR_PORT` | **Runtime** | Coordinator HTTP port (default **8000**) |
| `MATRIX_COORDINATOR_URL` | **Runtime** | (`proxy.mjs` only) Full coordinator base URL |

Defaults are chosen in **`matrix_env.cpp`** / **`proxy.mjs`** and **`scripts/matrix-env.sh`** (macOS vs Linux-style paths). No rebuild required when only env vars change.

## 4. Coordinator

`coordinator` reads **`swarm-config.json`** paths from the UI; no model root env in the coordinator binary.
