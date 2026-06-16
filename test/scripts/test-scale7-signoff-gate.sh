#!/usr/bin/env bash
# Validate SCALE-7 full roster sign-off artifact.
set -euo pipefail
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${FHS}/var/lib/cofiswarm/deploy/scale7-workload.json"
FAIL_KV="${SCALE_KV_FAIL:-0.75}"

[[ -f "$OUT" ]] || { echo "fail: missing $OUT (run make test-scale7-gate)" >&2; exit 1; }

python3 - "$OUT" "$FAIL_KV" <<'PY'
import json, sys
path, fail = sys.argv[1], float(sys.argv[2])
w = json.load(open(path))
rows = w.get("results", [])
roster = w.get("roster") or {}
peaks = [r["kv_pressure"] for r in rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
llama_exp = roster.get("llama_expected", 0)
llama_ok = len(roster.get("llama_ok") or [])
for pid, modes in [("P1", ("flat", "pipeline", "cascade", "router")), ("P2", ("flat", "pipeline", "cascade"))]:
    for m in modes:
        if not any(r.get("prompt") == pid and r.get("mode") == m and r.get("pass") for r in rows):
            print(f"fail: {pid}/{m}", file=sys.stderr)
            sys.exit(1)
if llama_ok < llama_exp or not roster.get("mlx_ok"):
    fail = roster.get("llama_fail") or []
    print(f"fail: roster coverage llama {llama_ok}/{llama_exp} missing={','.join(fail)} mlx={roster.get('mlx_ok')}", file=sys.stderr)
    sys.exit(1)
if any(not r.get("pass") for r in rows):
    print("fail: workload pass", file=sys.stderr)
    sys.exit(1)
if max_p >= fail:
    print(f"fail: peak kv {max_p:.3f} >= {fail}", file=sys.stderr)
    sys.exit(1)
print(f"ok: SCALE-7 signoff — 13-agent roster, {len(rows)} cases, peak kv {max_p:.3f}")
PY
