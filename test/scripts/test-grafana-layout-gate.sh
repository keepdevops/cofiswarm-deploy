#!/usr/bin/env bash
# Sprint 37: grafana dashboard JSON layout gate.
set -euo pipefail
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"
GRAF="${REPOS}/cofiswarm-grafana"
DASH="${GRAF}/dashboards/cofiswarm-ops.json"

[[ -f "$DASH" ]] || { echo "fail: missing $DASH" >&2; exit 1; }
[[ -f "${GRAF}/dashboards/cofiswarm-kv-pressure.json" ]] \
  || { echo "fail: missing kv pressure dashboard" >&2; exit 1; }
python3 - "$DASH" "${GRAF}/dashboards/cofiswarm-kv-pressure.json" <<'PY'
import json, sys
for path in sys.argv[1:]:
    d = json.load(open(path))
    assert d.get("title"), f"dashboard title {path}"
    assert isinstance(d.get("panels"), list), f"panels {path}"
    print(f"ok: grafana dashboard {d['title']!r} ({len(d['panels'])} panels)")
PY
[[ -f "${GRAF}/provisioning/dashboards/default.yaml" ]] \
  || { echo "fail: missing provisioning/dashboards/default.yaml" >&2; exit 1; }
echo "ok: grafana layout gate"
