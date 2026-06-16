#!/usr/bin/env bash
# SCALE-1 load gate — workload with KV peaks; fail if any peak >= 0.60.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${FHS}/var/lib/cofiswarm/deploy/scale1-workload.json"

"${ROOT}/test/scripts/test-scale0-workload.sh"
cp "${FHS}/var/lib/cofiswarm/deploy/scale0-workload.json" "$OUT"

python3 - "$OUT" <<'PY'
import json, sys
w = json.load(open(sys.argv[1]))
peaks = [r.get("kv_pressure") for r in w.get("results", []) if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
failed = [r for r in w.get("results", []) if not r.get("pass")]
infer = [r for r in w.get("results", []) if r.get("notes") != "infer"]
if failed:
    print(f"fail: workload {len(w['results'])-len(failed)}/{len(w['results'])} pass", file=sys.stderr)
    sys.exit(1)
if infer:
    print(f"fail: not all infer", file=sys.stderr)
    sys.exit(1)
if max_p >= 0.60:
    print(f"fail: peak kv_pressure {max_p:.3f} >= 0.60 (SCALE-GATES WARN/FAIL)", file=sys.stderr)
    sys.exit(1)
print(f"ok: SCALE-1 load gate — peak kv {max_p:.3f}, {len(w['results'])} cases → {sys.argv[1]}")
PY
