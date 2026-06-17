# Optional Prometheus + Grafana (not part of default `make up`).

See [cofiswarm-grafana/README](https://github.com/keepdevops/cofiswarm-grafana/blob/main/README.md) or:

```bash
make observability-up
make test-prometheus-up-gate
open http://127.0.0.1:3030
```

## Sign-off (Sprint 39)

```bash
make render-config && make up
make test-observability-signoff-gate
make render-observability-signoff
```

**Note:** Run commands without inline `# comments` — zsh/make may treat `#` as a target. Use `make observability-up` (not `compose/fragments/observability.yml`; removed in Sprint 38+).
