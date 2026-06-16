#!/usr/bin/env bash
# Validate SCALE-2 workload artifact exists and peak kv gate.
set -euo pipefail
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${FHS}/var/lib/cofiswarm/deploy/scale2-workload.json"
FAIL_KV="${SCALE_KV_FAIL:-0.75}"

[[ -f "$OUT" ]] || { echo "fail: missing $OUT (run make test-scale2-gate)" >&2; exit 1; }

python3 - "$OUT" "$FAIL_KV" <<'PY'
import json, sys
path, fail = sys.argv[1], float(sys.argv[2])
w = json.load(open(path))
rows = w.get("results", [])
bad = [r for r in rows if not r.get("pass")]
p3 = [r for r in rows if r.get("prompt") == "P3"]
peaks = [r["kv_pressure"] for r in rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
if bad:
    print(f"fail: {len(rows)-len(bad)}/{len(rows)} pass", file=sys.stderr)
    sys.exit(1)
if len(p3) < 3:
    print(f"fail: expected 3+ P3 rows, got {len(p3)}", file=sys.stderr)
    sys.exit(1)
if max_p >= fail:
    print(f"fail: peak kv {max_p:.3f} >= {fail}", file=sys.stderr)
    sys.exit(1)
print(f"ok: SCALE-2 signoff — {len(rows)} cases, {len(p3)} P3, peak kv {max_p:.3f}")
PY
