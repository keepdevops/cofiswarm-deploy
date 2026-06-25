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
  (the zmq bridge has no request/reply → route modes over direct HTTP). mode-flat is
  remapped to host **18021** because host 8021 is owned by the host `ob_code` Python stack.
- **mode-\*** — mounted `mode-configs/mode-<n>.yaml` (`infer_host: host.docker.internal`,
  `swarm_config_path`) + the 14-agent `cofiswarm-config/swarm-config.json`, plus
  `extra_hosts: host.docker.internal:host-gateway`.
- **slot-manager** — `ports: !reset []` (internal-only; host 8013 is taken).

## Mode images

`cofiswarm-mode-sdk v1.2.3` (which adds `infer_host`/`swarm_config_path` + the `/v1/models`
health probe) is published, and all four mode repos are bumped to it. So the modes build
normally from their `go.mod` — just `docker compose build mode-flat mode-pipeline mode-cascade
mode-router`; no `go.work` replace or bind-mounted binaries required.

> Legacy: before v1.2.3 was published the modes were cross-built against the local SDK and
> bind-mounted over `/usr/local/bin/cofiswarm-mode-<n>` (artifacts in the git-ignored
> `mode-bins/`). That stopgap is gone — the override no longer mounts binaries.

## Host inference servers

Not part of compose — launch on the host. See the `cofiswarm-host-llama-and-option-b` notes
(binary `/Users/Shared/llama/llama.cpp-master/build/bin/llama-server`, ports per
`cofiswarm-slot-manager/configs/endpoints.json`; MLX via `mlx_lm server`).
