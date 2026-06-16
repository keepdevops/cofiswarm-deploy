#!/usr/bin/env bash
# SCALE-6 gate — SCALE-5 + MLX pilot + peak kv thresholds.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${FHS}/var/lib/cofiswarm/deploy/scale6-workload.json"
SWARM="${COFISWARM_SWARM_CONFIG:-${FHS}/etc/cofiswarm/config/swarm-config.json}"
SWARM="${SWARM/#\~/$HOME}"
WARN_KV="${SCALE_KV_WARN:-0.60}"
FAIL_KV="${SCALE_KV_FAIL:-0.75}"

chmod +x "${ROOT}/test/scripts/test-scale6-workload.sh"
"${ROOT}/test/scripts/test-scale6-workload.sh"

python3 - "$OUT" "$SWARM" "$WARN_KV" "$FAIL_KV" <<'PY'
import json, sys

def mlx_audit(path):
    doc = json.load(open(path))
    scout = next((a for a in doc.get("agents", []) if a.get("name") == "mlx-scout"), None)
    if not scout:
        return {"pass": False}
    model = scout.get("model") or ""
    checks = {
        "engine_mlx": scout.get("engine") == "mlx",
        "max_concurrency_1": scout.get("max_concurrency", 1) == 1,
        "quant_4bit": "4bit" in model.lower(),
    }
    return {"pass": all(checks.values()), "checks": checks}

path, swarm, warn, fail = sys.argv[1:5]
warn, fail = float(warn), float(fail)
w = json.load(open(path))
rows = w.get("results", [])
audit = mlx_audit(swarm)
mlx_p1 = [r for r in rows if r.get("prompt") == "MLX-P1" and r.get("pass")]
mlx_dual = [r for r in rows if r.get("prompt") == "MLX-dual" and r.get("pass")]
peaks = [r["kv_pressure"] for r in rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
if not audit.get("pass"):
    print("fail: mlx turboquant audit", file=sys.stderr)
    sys.exit(1)
if not mlx_p1:
    print("fail: MLX-P1 infer", file=sys.stderr)
    sys.exit(1)
if len(mlx_dual) < 2:
    print(f"fail: expected 2 MLX-dual pass rows, got {len(mlx_dual)}", file=sys.stderr)
    sys.exit(1)
if any(not r.get("pass") for r in rows):
    sys.exit(1)
if max_p >= fail:
    print(f"fail: peak kv {max_p:.3f} >= {fail}", file=sys.stderr)
    sys.exit(1)
if max_p >= warn:
    print(f"warn: peak kv {max_p:.3f} in WARN band")
print(f"ok: SCALE-6 gate — mlx pilot pass, peak kv {max_p:.3f}, {len(rows)} cases → {path}")
PY
