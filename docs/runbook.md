# Cofiswarm daily ops (device)

**Profile:** `16gb` · **FHS:** `~/cofiswarm/fhs` · **UI:** http://127.0.0.1:3000

## Start / stop

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
export PATH="$HOME/.local/go/bin:$PATH"
make up
make observability-up    # optional Prometheus :9090 + Grafana :3030
```

```bash
make observability-down
make down                # if stack-down target exists; else kill host services manually
```

Or via monorepo: `matrix up` / `matrix down`

## Health checks

```bash
make test-stack-health-gate
make test-ui-ops-gate
make test-observability-signoff-gate   # includes optional Prometheus/Grafana
```

## After code changes

```bash
CGO_ENABLED=0 make build-dispatch build-modes build-observer
make ui-build    # after cofiswarm-ui nginx/API changes
make up
```

Refresh pins after commits: `./scripts/pin-repos.sh`

## Release sign-off (v1.1.0)

```bash
make test-release-signoff-gate
make render-release-signoff
```

Artifacts: `~/cofiswarmdev/docs/MIGRATION-SIGNOFF.md`, `OBSERVABILITY-SIGNOFF.md`, `DEVICE-RELEASE-SIGNOFF.md`

## Paste traps

- Do **not** paste inline `# comments` on the same line as `make` targets.
- Do **not** paste `(:9090)` — use `make observability-up`.
