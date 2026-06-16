#!/usr/bin/env bash
# Validate SCALE-6 workload artifact.
set -euo pipefail
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${FHS}/var/lib/cofiswarm/deploy/scale6-workload.json"
SWARM="${COFISWARM_SWARM_CONFIG:-${FHS}/etc/cofiswarm/config/swarm-config.json}"
SWARM="${SWARM/#\~/$HOME}"
FAIL_KV="${SCALE_KV_FAIL:-0.75}"

[[ -f "$OUT" ]] || { echo "fail: missing $OUT (run make test-scale6-gate)" >&2; exit 1; }

python3 - "$OUT" "$SWARM" "$FAIL_KV" <<'PY'
import json, sys

def mlx_audit(path):
    doc = json.load(open(path))
    scout = next((a for a in doc.get("agents", []) if a.get("name") == "mlx-scout"), None)
    if not scout:
        return False
    model = scout.get("model") or ""
    return (
        scout.get("engine") == "mlx"
        and scout.get("max_concurrency", 1) == 1
        and "4bit" in model.lower()
    )

path, swarm, fail = sys.argv[1:4]
fail = float(fail)
w = json.load(open(path))
rows = w.get("results", [])
mlx_p1 = [r for r in rows if r.get("prompt") == "MLX-P1" and r.get("pass")]
mlx_dual = [r for r in rows if r.get("prompt") == "MLX-dual" and r.get("pass")]
peaks = [r["kv_pressure"] for r in rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
if not mlx_audit(swarm):
    print("fail: mlx turboquant audit", file=sys.stderr)
    sys.exit(1)
if not mlx_p1 or len(mlx_dual) < 2:
    print("fail: mlx pilot infer", file=sys.stderr)
    sys.exit(1)
if any(not r.get("pass") for r in rows):
    print("fail: workload pass", file=sys.stderr)
    sys.exit(1)
if max_p >= fail:
    print(f"fail: peak kv {max_p:.3f} >= {fail}", file=sys.stderr)
    sys.exit(1)
print(f"ok: SCALE-6 signoff — {len(rows)} cases, mlx pilot pass, peak kv {max_p:.3f}")
PY
