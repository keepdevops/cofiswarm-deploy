# Option B overlay — containerized control plane → host inference

`dispatch-host-infer.override.yml` overlays the launcher compose so the Dockerized control
plane reaches the **host** llama/MLX servers (Metal, outside compose) and routes modes over
direct HTTP. Apply it on top of the launcher compose:

```sh
cd ../../cofiswarm-launcher/compose
OV=../../cofiswarm-deploy/compose/dispatch-host-infer.override.yml
docker compose -f docker-compose.yml -f "$OV" up -d \
  dispatch mode-flat mode-pipeline mode-cascade mode-router slot-manager agent-registry kvpool
```

## What it wires (all option B: env-configurable, deployment-agnostic)

- **dispatch** — `COFISWARM_AGENT_HOST=host.docker.internal` (per-agent llama caller),
  `COFISWARM_MODE_HOST` + published mode ports (mode Execute), `COFISWARM_ROUTE_BUS=""`
  (default: route modes over direct HTTP). mode-flat is
  remapped to host **18021** because host 8021 is owned by the host `ob_code` Python stack.
- **mode-\*** — mounted `mode-configs/mode-<n>.yaml` (`infer_host: host.docker.internal`,
  `swarm_config_path`) + the 14-agent `cofiswarm-config/swarm-config.json`, plus
  `extra_hosts: host.docker.internal:host-gateway`.
- **slot-manager** — `ports: !reset []` (internal-only; host 8013 is taken).

## Optional: route modes over the ZMQ bus (request/reply)

The zmq bridge now has a request/reply leg (ROUTER on `:5558`, see
`cofiswarm-zmq-bridge` README). Overlay `mode-bus-responders.override.yml` flips dispatch to
`COFISWARM_ROUTE_BUS=1` and switches the launcher's `responder-{flat,pipeline,cascade,router}`
from NATS to zmq (`COFISWARM_BUS=zmq`, dialing `zmq-bridge:5558`). Then `dispatch.Execute`
routes `swarm.observer.mode.<mode>` through `POST /v1/request`; a dead responder surfaces as
503/504 instead of a direct-HTTP error. Enable at bring-up:

```
COFISWARM_ROUTE_BUS_MODES=1 scripts/start-stack.sh
```

Or manually, appending the overlay + responders to the launcher invocation (see the header of
`compose/mode-bus-responders.override.yml`). Reversible: omit the overlay to fall back to
direct HTTP. The 4 mode responders self-announce presence, so they no longer need the
`announce-responders.sh` fakes (model responders + the UI still do).

## Optional: native ZMQ PUB presence

By default components publish presence over HTTP `/v1/publish`. Overlay
`native-pub.override.yml` sets `COFISWARM_ZMQ_PUBLISH_ADDR=tcp://zmq-bridge:5556` on the
self-announcing components (dispatch, slot-manager, kvpool, the 4 modes) so their
`buspresence.StartPresence` publishes over a native ZMQ PUB socket to the bridge ingress wire
instead. Enable with `COFISWARM_NATIVE_PUB=1 scripts/start-stack.sh`.

Prerequisite: the component image must be built against an `observer-sdk` that includes native
PUB (observer-sdk PR #2 / its tag). Until then the env is ignored (older `StartPresence` keeps
using HTTP), so it's harmless to set early. agent-registry is excluded — its roster
`AnnounceMembers` still uses HTTP (native PUB covers single-component presence only).

## Mode images

`cofiswarm-mode-sdk v1.2.3` (which adds `infer_host`/`swarm_config_path` + the `/v1/models`
health probe) is published, and all four mode repos are bumped to it. So the modes build
normally from their `go.mod` — just `docker compose build mode-flat mode-pipeline mode-cascade
mode-router`; no `go.work` replace or bind-mounted binaries required.

> Legacy: before v1.2.3 was published the modes were cross-built against the local SDK and
> bind-mounted over `/usr/local/bin/cofiswarm-mode-<n>` (artifacts in a `mode-bins/` dir).
> That stopgap is gone — the override no longer mounts binaries, and the `mode-bins/`
> directory (and its `.gitignore` entry) have been removed.

## Host inference servers

Not part of compose — they run on the host (Metal). `scripts/start-host-inference.sh` launches
all five (4 llama.cpp + 1 MLX) idempotently, port→model per
`cofiswarm-slot-manager/configs/endpoints.json`; it also normalizes the MLX model's
`tokenizer_class` quirk so a fresh pull can't break mlx-scout.

## Host RAG services

Per-agent RAG (`use_rag` agents) needs the `cofiswarm-rag` service, which also runs on the host.
`scripts/start-host-rag.sh` launches all three idempotently: the **nomic embeddings server**
(:8090, `llama-server --embeddings` on `nomic-embed-text-v1.5.f16.gguf`), the **rag service**
(:8001, serverless sqlite-vec, nomic embedder, DB at `$COFISWARM_VAR_LIB/rag/index/rag.db` —
**non-FHS**), and the **rag-worker** (:8018). Binaries install to `/Users/Shared/cofiswarm/bin`
(rebuilt from the repos if missing; rag needs CGO for sqlite-vec). dispatch reaches :8001 via
`COFISWARM_RAG_URL=http://host.docker.internal:8001` + `COFISWARM_RAG_ENABLED=1` (in the override).

**Reboot survival** (`make install-launchd` runs all three installers):
- `install-host-inference-launchd.sh` → `com.cofiswarm.host-inference` (RunAtLoad +
  AbandonProcessGroup): relaunches the 5 inference servers at login.
- `install-host-rag-launchd.sh` → `com.cofiswarm.host-rag` (RunAtLoad + AbandonProcessGroup):
  relaunches nomic-embed + rag + worker at login.
- `install-announcer-launchd.sh` → `com.cofiswarm.announcer` (RunAtLoad + KeepAlive):
  keeps the broker-free responder presence loop alive across reboots/crashes.
- The Docker containers carry `restart: unless-stopped`, so Docker Desktop restores them on boot.

Together these cover the whole stack on reboot; nothing needs a manual bring-up.

## One-command bring-up

`scripts/start-stack.sh` cold-starts the whole stack in order — host inference → Docker control
plane (launcher compose + this overlay) → responder presence announcer — then health-gates all
endpoints. Idempotent. (The Docker containers carry `restart: unless-stopped`, so they self-heal
across reboots on their own; this script is for cold starts and manual bring-up.)
