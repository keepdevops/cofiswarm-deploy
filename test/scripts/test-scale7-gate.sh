#!/usr/bin/env bash
# SCALE-7 gate — full roster sign-off + peak kv thresholds.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${FHS}/var/lib/cofiswarm/deploy/scale7-workload.json"
WARN_KV="${SCALE_KV_WARN:-0.60}"
FAIL_KV="${SCALE_KV_FAIL:-0.75}"

chmod +x "${ROOT}/test/scripts/test-scale7-workload.sh"
"${ROOT}/test/scripts/test-scale7-workload.sh"

python3 - "$OUT" "$WARN_KV" "$FAIL_KV" <<'PY'
import json, sys
path, warn, fail = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
w = json.load(open(path))
rows = w.get("results", [])
roster = w.get("roster") or {}
peaks = [r["kv_pressure"] for r in rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0

def mode_pass(pid, modes):
    for m in modes:
        hit = [r for r in rows if r.get("prompt") == pid and r.get("mode") == m and r.get("pass")]
        if not hit:
            return False, m
    return True, None

ok_p1, miss = mode_pass("P1", ("flat", "pipeline", "cascade", "router"))
if not ok_p1:
    print(f"fail: P1 mode {miss} missing or failed", file=sys.stderr)
    sys.exit(1)
ok_p2, miss = mode_pass("P2", ("flat", "pipeline", "cascade"))
if not ok_p2:
    print(f"fail: P2 mode {miss} missing or failed", file=sys.stderr)
    sys.exit(1)

llama_exp = roster.get("llama_expected", 0)
llama_ok = len(roster.get("llama_ok") or [])
if llama_ok < llama_exp:
    fail = roster.get("llama_fail") or []
    print(f"fail: roster llama {llama_ok}/{llama_exp} missing={','.join(fail)}", file=sys.stderr)
    sys.exit(1)
if not roster.get("mlx_ok"):
    mlx_fail = [r for r in rows if r.get("mode") == "mlx" and not r.get("pass")]
    hint = mlx_fail[0].get("notes", "") if mlx_fail else "MLX-P1 missing"
    print(f"fail: mlx-scout ({hint})", file=sys.stderr)
    sys.exit(1)
if roster.get("expected", 0) < 13:
    print("fail: expected 13 agents in roster", file=sys.stderr)
    sys.exit(1)
if any(not r.get("pass") for r in rows):
    sys.exit(1)
if max_p >= fail:
    print(f"fail: peak kv {max_p:.3f} >= {fail}", file=sys.stderr)
    sys.exit(1)
if max_p >= warn:
    print(f"warn: peak kv {max_p:.3f} in WARN band")
print(f"ok: SCALE-7 gate — roster {llama_ok}/{llama_exp} llama + mlx, peak kv {max_p:.3f}, {len(rows)} cases → {path}")
PY
