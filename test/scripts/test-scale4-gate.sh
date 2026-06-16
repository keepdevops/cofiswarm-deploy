#!/usr/bin/env bash
# SCALE-4 gate — workload + KV audit + peak kv thresholds.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${FHS}/var/lib/cofiswarm/deploy/scale4-workload.json"
WARN_KV="${SCALE_KV_WARN:-0.60}"
FAIL_KV="${SCALE_KV_FAIL:-0.75}"

chmod +x "${ROOT}/test/scripts/test-scale4-workload.sh"
"${ROOT}/test/scripts/test-scale4-workload.sh"

python3 - "$OUT" "$WARN_KV" "$FAIL_KV" <<'PY'
import json, sys
path, warn, fail = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
w = json.load(open(path))
rows = w.get("results", [])
audit = w.get("kv_audit") or {}
peaks = [r["kv_pressure"] for r in rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
dual = [r for r in rows if r.get("prompt") == "P4-pipeline-dual"]
if not audit.get("pass"):
    print("fail: kv quant audit", file=sys.stderr)
    sys.exit(1)
if len(dual) < 2:
    print(f"fail: expected 2 dual pipeline rows, got {len(dual)}", file=sys.stderr)
    sys.exit(1)
if any(not r.get("pass") for r in rows):
    sys.exit(1)
if max_p >= fail:
    print(f"fail: peak kv {max_p:.3f} >= {fail}", file=sys.stderr)
    sys.exit(1)
if max_p >= warn:
    print(f"warn: peak kv {max_p:.3f} in WARN band")
print(f"ok: SCALE-4 gate — peak kv {max_p:.3f}, kv audit pass, {len(rows)} cases → {path}")
PY
