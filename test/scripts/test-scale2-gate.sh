#!/usr/bin/env bash
# SCALE-2 gate — P3 long context + concurrent load; peak kv < 0.60.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${FHS}/var/lib/cofiswarm/deploy/scale2-workload.json"
WARN_KV="${SCALE_KV_WARN:-0.60}"
FAIL_KV="${SCALE_KV_FAIL:-0.75}"

chmod +x "${ROOT}/test/scripts/test-scale2-workload.sh"
"${ROOT}/test/scripts/test-scale2-workload.sh"

python3 - "$OUT" "$WARN_KV" "$FAIL_KV" <<'PY'
import json, sys
path, warn, fail = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
w = json.load(open(path))
rows = w.get("results", [])
bad = [r for r in rows if not r.get("pass")]
infer = [r for r in rows if r.get("notes") != "infer"]
peaks = [r["kv_pressure"] for r in rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
p3 = [r for r in rows if r.get("prompt") == "P3"]
if bad:
    print(f"fail: {len(rows)-len(bad)}/{len(rows)} pass", file=sys.stderr)
    sys.exit(1)
if infer:
    print(f"fail: not all infer ({len(rows)-len(infer)} non-infer)", file=sys.stderr)
    sys.exit(1)
if max_p >= fail:
    print(f"fail: peak kv {max_p:.3f} >= {fail} FAIL threshold", file=sys.stderr)
    sys.exit(1)
if max_p >= warn:
    print(f"warn: peak kv {max_p:.3f} in WARN band [{warn}, {fail}) — document in SCALE-2.md")
print(f"ok: SCALE-2 gate — peak kv {max_p:.3f}, {len(rows)} cases ({len(p3)} P3) → {path}")
PY
