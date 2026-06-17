#!/usr/bin/env bash
# Sprint 37: grafana dashboard JSON layout gate.
set -euo pipefail
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"
GRAF="${REPOS}/cofiswarm-grafana"
DASH="${GRAF}/dashboards/cofiswarm-ops.json"

[[ -f "$DASH" ]] || { echo "fail: missing $DASH" >&2; exit 1; }
python3 - "$DASH" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("title"), "dashboard title"
assert isinstance(d.get("panels"), list), "panels"
print(f"ok: grafana dashboard {d['title']!r} ({len(d['panels'])} panels)")
PY
[[ -f "${GRAF}/provisioning/dashboards/default.yaml" ]] \
  || { echo "fail: missing provisioning/dashboards/default.yaml" >&2; exit 1; }
echo "ok: grafana layout gate"
