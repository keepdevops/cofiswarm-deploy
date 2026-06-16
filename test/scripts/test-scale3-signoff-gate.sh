#!/usr/bin/env bash
# Validate SCALE-3 workload artifact.
set -euo pipefail
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${FHS}/var/lib/cofiswarm/deploy/scale3-workload.json"
FAIL_KV="${SCALE_KV_FAIL:-0.75}"

[[ -f "$OUT" ]] || { echo "fail: missing $OUT (run make test-scale3-gate)" >&2; exit 1; }

python3 - "$OUT" "$FAIL_KV" <<'PY'
import json, sys
path, fail = sys.argv[1], float(sys.argv[2])
w = json.load(open(path))
rows = w.get("results", [])
heavy = [r for r in rows if "P3-heavy" in str(r.get("prompt")) or "concurrent" in str(r.get("prompt"))]
peaks = [r["kv_pressure"] for r in rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
if any(not r.get("pass") for r in rows):
    print("fail: workload pass", file=sys.stderr)
    sys.exit(1)
if len(heavy) < 4:
    print(f"fail: expected 4+ SCALE-3 heavy rows, got {len(heavy)}", file=sys.stderr)
    sys.exit(1)
if max_p >= fail:
    print(f"fail: peak kv {max_p:.3f} >= {fail}", file=sys.stderr)
    sys.exit(1)
print(f"ok: SCALE-3 signoff — {len(rows)} cases, peak kv {max_p:.3f}")
PY
