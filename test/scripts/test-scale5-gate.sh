#!/usr/bin/env bash
# SCALE-5 gate — extended concurrent load + peak kv thresholds.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${FHS}/var/lib/cofiswarm/deploy/scale5-workload.json"
WARN_KV="${SCALE_KV_WARN:-0.60}"
FAIL_KV="${SCALE_KV_FAIL:-0.75}"

chmod +x "${ROOT}/test/scripts/test-scale5-workload.sh"
"${ROOT}/test/scripts/test-scale5-workload.sh"

python3 - "$OUT" "$WARN_KV" "$FAIL_KV" <<'PY'
import json, sys
path, warn, fail = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
w = json.load(open(path))
rows = w.get("results", [])
peaks = [r["kv_pressure"] for r in rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
triple = [r for r in rows if r.get("prompt") == "P4-cascade-triple"]
burst = [r for r in rows if r.get("prompt") == "P2-mixed-burst"]
if len(triple) < 3 or any(not r.get("pass") for r in triple):
    print(f"fail: expected 3 pass cascade-triple rows, got {len(triple)}", file=sys.stderr)
    sys.exit(1)
if len(burst) < 4 or any(not r.get("pass") for r in burst):
    print(f"fail: expected 4 pass mixed-burst rows, got {len(burst)}", file=sys.stderr)
    sys.exit(1)
if any(not r.get("pass") for r in rows):
    sys.exit(1)
if max_p >= fail:
    print(f"fail: peak kv {max_p:.3f} >= {fail}", file=sys.stderr)
    sys.exit(1)
if max_p >= warn:
    print(f"warn: peak kv {max_p:.3f} in WARN band")
print(f"ok: SCALE-5 gate — peak kv {max_p:.3f}, {len(rows)} cases → {path}")
PY
