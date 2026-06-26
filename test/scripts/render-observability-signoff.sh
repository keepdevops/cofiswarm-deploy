#!/usr/bin/env bash
# Render docs/OBSERVABILITY-SIGNOFF.md after observability signoff gate.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/OBSERVABILITY-SIGNOFF.md"

"${ROOT}/test/scripts/test-observability-signoff-gate.sh"

python3 - "$OUT" <<'PY'
import datetime, sys
from pathlib import Path

ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
md = f"""# Observability sign-off

**Date:** {ts}  
**Stack:** observer :8016 · Prometheus :9090 · Grafana :3030 · zmq-bridge :5555

## Verdict

**Host metrics + optional Prometheus/Grafana + ZMQ:** PASS

## Gates

| Gate | Scope |
|------|-------|
| `test-observability-gate` | observer plugins, grafana layout, /metrics |
| `test-zmq-bridge-gate` | topics + publish + real egress wire (native SUB on :5557) |
| `test-prometheus-up-gate` | scrape + PromQL + Grafana |

```bash
make up
make observability-up
make test-observability-signoff-gate
```

See `cofiswarm-deploy/docs/observability.md`.
"""
Path(sys.argv[1]).write_text(md)
print(f"rendered {sys.argv[1]}")
PY
