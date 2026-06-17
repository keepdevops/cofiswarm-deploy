#!/usr/bin/env bash
# Optional Prometheus + Grafana gate — requires `make observability-up`.
set -euo pipefail
PROM="${PROMETHEUS_URL:-http://127.0.0.1:9090}"
GRAF="${GRAFANA_URL:-http://127.0.0.1:3030}"

curl -sf --max-time 5 "${PROM}/-/healthy" >/dev/null || {
  echo "fail: prometheus not healthy at ${PROM} (run make observability-up)" >&2
  exit 1
}
echo "ok: prometheus healthy"

python3 - "$PROM" <<'PY'
import json, sys, urllib.request
base = sys.argv[1].rstrip("/")
raw = urllib.request.urlopen(f"{base}/api/v1/targets", timeout=10).read()
data = json.loads(raw)["data"]["activeTargets"]
obs = [t for t in data if t.get("labels", {}).get("job") == "cofiswarm-observer"]
if not obs:
    print("fail: no cofiswarm-observer scrape target", file=sys.stderr)
    sys.exit(1)
t = obs[0]
if t.get("health") != "up":
    print(f"fail: observer target {t.get('health')} — is observer :8016 up?", file=sys.stderr)
    sys.exit(1)
print("ok: prometheus scrapes observer :8016")
PY

curl -sf --max-time 5 "${PROM}/api/v1/query?query=cofiswarm_kv_pressure_usage" | python3 -c "
import json, sys
d = json.load(sys.stdin)
r = d.get('data', {}).get('result', [])
if not r:
    print('fail: no cofiswarm_kv_pressure_usage series in prometheus', file=sys.stderr)
    sys.exit(1)
print(f'ok: prometheus query — {len(r)} kv pressure series')
"

curl -sf --max-time 5 "${GRAF}/api/health" >/dev/null || {
  echo "fail: grafana not reachable at ${GRAF}" >&2
  exit 1
}
echo "ok: grafana healthy"
echo "ok: optional observability stack"
