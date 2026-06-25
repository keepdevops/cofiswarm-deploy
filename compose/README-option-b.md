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

## Mode binaries (`mode-bins/`, git-ignored)

The mode repos pin `cofiswarm-mode-sdk v0.1.0`, which predates `infer_host`/`swarm_config_path`.
Until a newer mode-sdk tag is published and the mode repos are bumped, build the modes against
the local SDK (the repo `go.work` has the `replace`) and bind-mount the static binaries:

```sh
cd ../../   # repos root (go.work)
for m in flat pipeline cascade router; do
  (cd cofiswarm-mode-$m && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
     go build -trimpath -o ../cofiswarm-deploy/compose/mode-bins/cofiswarm-mode-$m ./cmd/cofiswarm-mode-$m)
done
```

## Host inference servers

Not part of compose — launch on the host. See the `cofiswarm-host-llama-and-option-b` notes
(binary `/Users/Shared/llama/llama.cpp-master/build/bin/llama-server`, ports per
`cofiswarm-slot-manager/configs/endpoints.json`; MLX via `mlx_lm server`).
