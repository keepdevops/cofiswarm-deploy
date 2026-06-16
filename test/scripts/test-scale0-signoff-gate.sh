#!/usr/bin/env bash
# Validate SCALE-0 artifacts (pressure 4/4 llama ok + workload 8/8 infer).
set -euo pipefail
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
PRESSURE="${FHS}/var/lib/cofiswarm/deploy/scale0-pressure.json"
WORKLOAD="${FHS}/var/lib/cofiswarm/deploy/scale0-workload.json"

for f in "$PRESSURE" "$WORKLOAD"; do
  [[ -f "$f" ]] || { echo "fail: missing $f (run make test-scale0-probe && make test-scale0-workload)" >&2; exit 1; }
done

python3 - "$PRESSURE" "$WORKLOAD" <<'PY'
import json, sys
pressure_path, workload_path = sys.argv[1:3]
p = json.load(open(pressure_path))
w = json.load(open(workload_path))
llama = [e for e in p.get("pressure", []) if e.get("backend") == "llama"]
ok_p = [e for e in llama if e.get("ok")]
if len(ok_p) != len(llama) or not llama:
    print(f"fail: pressure {len(ok_p)}/{len(llama)} llama ok", file=sys.stderr)
    sys.exit(1)
rows = w.get("results", [])
bad = [r for r in rows if not r.get("pass")]
infer = [r for r in rows if r.get("notes") != "infer"]
if bad:
    print(f"fail: workload {len(rows)-len(bad)}/{len(rows)} pass", file=sys.stderr)
    sys.exit(1)
if infer:
    print(f"fail: workload not all infer ({len(rows)-len(infer)}/{len(rows)})", file=sys.stderr)
    sys.exit(1)
print(f"ok: SCALE-0 signoff — pressure {len(ok_p)}/{len(llama)} llama, workload {len(rows)}/{len(rows)} infer")
PY
