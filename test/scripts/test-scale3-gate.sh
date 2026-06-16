#!/usr/bin/env bash
# SCALE-3 gate — workload + peak kv thresholds.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${FHS}/var/lib/cofiswarm/deploy/scale3-workload.json"
WARN_KV="${SCALE_KV_WARN:-0.60}"
FAIL_KV="${SCALE_KV_FAIL:-0.75}"

chmod +x "${ROOT}/test/scripts/test-scale3-workload.sh"
"${ROOT}/test/scripts/test-scale3-workload.sh"

python3 - "$OUT" "$WARN_KV" "$FAIL_KV" <<'PY'
import json, sys
path, warn, fail = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
w = json.load(open(path))
rows = w.get("results", [])
peaks = [r["kv_pressure"] for r in rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
if any(not r.get("pass") for r in rows):
    sys.exit(1)
if max_p >= fail:
    print(f"fail: peak kv {max_p:.3f} >= {fail}", file=sys.stderr)
    sys.exit(1)
if max_p >= warn:
    print(f"warn: peak kv {max_p:.3f} in WARN band")
print(f"ok: SCALE-3 gate — peak kv {max_p:.3f}, {len(rows)} cases → {path}")
PY
