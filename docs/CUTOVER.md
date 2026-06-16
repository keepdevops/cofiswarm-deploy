# Sprint 14 — Cutover complete

## Checklist

- [x] `bin/matrix.mjs` → `cofiswarm-deploy` `stack-up` / `stack-down`
- [x] Sessions/history canonical under `~/cofiswarm/fhs/var/lib/cofiswarm/dispatch/`
- [x] `cofiswarm-coordinator` + `cofiswarm-proxy` archived
- [x] `repos.json` pins compatible SHAs
- [x] Tags: monorepo `v3.0.0-bridge`, deploy `v1.0.0`

## Commands

```bash
matrix up              # FHS stack (Go control plane + compose)
matrix down
matrix --legacy        # old C++ proxy + coordinator
brewctl launch         # still available; prefer matrix up
```

## Releases

| Artifact | Tag |
|----------|-----|
| cofiswarmdev monorepo | `v3.0.0-bridge` |
| cofiswarm-deploy | `v1.0.0` |
