#!/usr/bin/env bash
# Validate SCALE-4 workload artifact.
set -euo pipefail
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${FHS}/var/lib/cofiswarm/deploy/scale4-workload.json"
SWARM="${COFISWARM_SWARM_CONFIG:-${FHS}/etc/cofiswarm/config/swarm-config.json}"
SWARM="${SWARM/#\~/$HOME}"
FAIL_KV="${SCALE_KV_FAIL:-0.75}"

[[ -f "$OUT" ]] || { echo "fail: missing $OUT (run make test-scale4-gate)" >&2; exit 1; }
[[ -f "$SWARM" ]] || { echo "fail: missing $SWARM (run make up / render-config)" >&2; exit 1; }

python3 - "$OUT" "$SWARM" "$FAIL_KV" <<'PY'
import json, sys

def kv_audit(path):
    doc = json.load(open(path))
    rows = []
    ok = True
    for a in doc.get("agents", []):
        if a.get("engine") != "llama":
            continue
        args = a.get("extra_args") or []
        kt = kv = None
        for i, x in enumerate(args):
            if x == "--cache-type-k" and i + 1 < len(args):
                kt = args[i + 1]
            if x == "--cache-type-v" and i + 1 < len(args):
                kv = args[i + 1]
        row = {"agent": a.get("name"), "cache_type_k": kt, "cache_type_v": kv}
        if kt is None or kv is None:
            row["pass"] = False
            ok = False
        else:
            row["pass"] = True
        rows.append(row)
    return {"pass": ok, "agents": rows}

path, swarm, fail = sys.argv[1], sys.argv[2], float(sys.argv[3])
w = json.load(open(path))
rows = w.get("results", [])
audit = kv_audit(swarm)
dual = [r for r in rows if r.get("prompt") == "P4-pipeline-dual"]
peaks = [r["kv_pressure"] for r in rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
if not audit.get("pass"):
    bad = [a["agent"] for a in audit.get("agents", []) if not a.get("pass")]
    print(f"fail: kv quant audit ({', '.join(bad) or 'unknown'})", file=sys.stderr)
    sys.exit(1)
if len(dual) < 2 or any(not r.get("pass") for r in dual):
    print("fail: dual pipeline cases", file=sys.stderr)
    sys.exit(1)
if any(not r.get("pass") for r in rows):
    print("fail: workload pass", file=sys.stderr)
    sys.exit(1)
if max_p >= fail:
    print(f"fail: peak kv {max_p:.3f} >= {fail}", file=sys.stderr)
    sys.exit(1)
print(f"ok: SCALE-4 signoff — {len(rows)} cases, kv audit pass, peak kv {max_p:.3f}")
PY
