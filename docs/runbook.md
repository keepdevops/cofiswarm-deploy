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
make down
```

Or via monorepo: `matrix up` / `matrix down`

## Login auto-start (optional)

```bash
make install-launchd
make launchd-status
LAUNCHD_REQUIRE=1 make test-launchd-live-gate
make uninstall-launchd
```

Logs: `~/cofiswarm/fhs/var/log/cofiswarm/launchd-stack-up.{log,err}`

## Health checks

```bash
make ops-check                         # stack health + UI smoke
make test-device-ops-signoff-gate      # full device ops incl. launchd template
make test-observability-signoff-gate   # includes optional Prometheus/Grafana
```

## After code changes

```bash
CGO_ENABLED=0 make build-dispatch build-modes build-observer build-convert
make ui-build    # after cofiswarm-ui nginx/API changes
make up
```

Refresh pins after commits: `./scripts/pin-repos.sh`

## Release sign-off (v1.1.0)

```bash
./scripts/pin-repos.sh
make test-release-signoff-gate
make render-release-signoff    # skips re-running gate
make tag-release               # local annotated tags
make test-release-tag-gate
```

Or: `make release` (all four steps)

Push tags: `git -C ~/cofiswarm/repos/cofiswarm-deploy push origin v1.1.0`

## UI security (Sprint 43)

```bash
make test-ui-security-gate
make security    # gate + SECURITY-SIGNOFF.md
```

After `package.json` changes: `cd ~/cofiswarm/repos/cofiswarm-ui && npm install && npm test`

## CI (Sprint 44)

```bash
make test-ci-static-gate          # local / GitHub Actions
make ci                           # static + CI-SIGNOFF.md
COFISWARM_CI_LIVE=1 make test-ci-signoff-gate   # + pins + stack health on device
```

Workflow: `.github/workflows/ci.yml` (Node **24**, `actions/setup-node@v6`, runs on push/PR to `main`).

## Post-migration capstone (Sprint 46)

```bash
./scripts/pin-repos.sh
make post-migration
make post-migration-live   # pin-repos + sidecars + device ops (stack up)
```

After local commits to any pinned repo, run `./scripts/pin-repos.sh` before `make post-migration`.

## Repo layout (Sprint 47)

```bash
make test-repo-layout-gate      # 43 repos: README, Makefile, test/standalone, no submodules
make repo-layout
./scripts/install-repo-ci.sh    # optional: copy per-repo ci template
```

## Go workspace (Sprint 48)

```bash
./scripts/render-go-workspace.sh
CGO_ENABLED=0 make build-modes
make go-modules
```

`~/cofiswarm/repos/go.work` links sibling Go modules; `mode-sdk` is a workspace `replace` (not `../` in each `go.mod`).

## Per-repo CI (Sprint 49)

```bash
./scripts/install-repo-ci.sh
make repo-ci
make go-ci                    # mode-* CI checks out mode-sdk + go.work
```

## Paste traps

- Do **not** paste inline `# comments` on the same line as `make` targets.
- Do **not** paste `(:9090)` — use `make observability-up`.
