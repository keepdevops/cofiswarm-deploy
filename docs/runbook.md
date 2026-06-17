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
make install-launchd    # writes plist + launchctl bootstrap (required after reboot if booted out)
make launchd-status     # plist: … / state: loaded|not loaded
LAUNCHD_REQUIRE=1 make test-launchd-live-gate
make uninstall-launchd
```

A plist on disk does **not** mean loaded — re-run `make install-launchd` if `state: not loaded`.

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
./scripts/tag-all-repos.sh       # v1.1.0 @ pin SHA on all 43 repos
make release-cut
PUSH_DRY_RUN=1 ./scripts/push-all-repos.sh
./scripts/pin-repos.sh && git add repos.json && git commit -m "Pin repos before push."
./scripts/tag-all-repos.sh
./scripts/push-all-repos.sh
PUSH_TAG_FORCE=1 ./scripts/push-all-repos.sh   # if remote v1.1.0 at old SHA
REMOTE_REQUIRE=1 make remote-push
```

Or: `make release` (signoff + tag-all + gate).

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

## Migration complete (Sprint 57)

Final capstone after release cut + remote push:

```bash
./scripts/pin-repos.sh
make migration-complete
REMOTE_REQUIRE=1 make migration-complete   # after ./scripts/push-all-repos.sh
```

Renders `~/cofiswarmdev/docs/MIGRATION-COMPLETE-SIGNOFF.md`. The 43-repo device migration is complete when this gate passes with `REMOTE_REQUIRE=1`.

## Remote complete (Sprint 58)

Push runbook closure — hard origin verification after push:

```bash
./scripts/verify-remote-push.sh              # status summary (non-fatal)
PUSH_DRY_RUN=1 ./scripts/push-all-repos.sh   # preview
./scripts/push-all-repos.sh
PUSH_TAG_FORCE=1 ./scripts/push-all-repos.sh   # if origin tag at old SHA
REMOTE_REQUIRE=1 make remote-complete
```

Renders `~/cofiswarmdev/docs/REMOTE-COMPLETE-SIGNOFF.md`. Unlike `remote-push`, this gate always requires `REMOTE_REQUIRE=1` (no soft-pass).

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
make go-ci                    # mode-* GOPRIVATE + published mode-sdk v0.1.0
./scripts/tag-mode-sdk.sh
make mode-sdk-release
make phase6                   # optional infer/adapter/tools scaffolds
make phase7                   # adapter-agentic stub
make optional-repos           # phase 6 + 7
```

## Paste traps

- Do **not** paste inline `# comments` on the same line as `make` targets.
- Do **not** paste `(:9090)` — use `make observability-up`.
