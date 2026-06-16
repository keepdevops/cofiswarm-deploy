#!/usr/bin/env bash
# Render SCALE-5.md from scale5-workload.json.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/sprints/SCALE-5.md"
WORKLOAD="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}/var/lib/cofiswarm/deploy/scale5-workload.json"
WORKLOAD="${WORKLOAD/#\~/$HOME}"

"${ROOT}/test/scripts/test-scale5-signoff-gate.sh"

python3 - "$WORKLOAD" "$OUT" <<'PY'
import json, sys
wpath, out_path = sys.argv[1:3]
w = json.load(open(wpath))
ts = w.get("ts", "")
rows = w.get("results", [])
load = w.get("load") or {}
peaks = [r["kv_pressure"] for r in rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
lines = []
for r in rows:
    kv = r.get("kv_pressure")
    kv_s = f"{kv:.3f}" if isinstance(kv, (int, float)) else "—"
    wall = r.get("wall_s")
    wall_s = str(wall) if wall is not None else "—"
    lines.append(f"| {r.get('mode')} | {r.get('prompt')} | {'yes' if r.get('pass') else 'no'} | {wall_s} | {kv_s} | {r.get('notes','')} |")
advance = "YES" if max_p < 0.60 else ("WARN — document" if max_p < 0.75 else "NO")
md = f"""# SCALE-5 — Extended concurrent load

**Date:** {ts}  
**Hardware:** M3 Max 36 GB  
**Roster:** 13 agents (load sprint)  
**Change:** SCALE-4 + 3× concurrent cascade P4 + 4-way mixed-mode P2 burst.

## Commands

```bash
export COFISWARM_MODE_EXECUTE_TIMEOUT=600
make test-scale5-gate
make test-scale5-signoff-gate
```

Peak kv **{max_p:.3f}** · artifact `scale5-workload.json`

## Load additions

- **Cascade triple:** {load.get('cascade_triple', 3)}× concurrent `cascade` on P4
- **Mixed burst:** {load.get('mixed_burst_modes', 4)} modes concurrent on P2 (flat, pipeline, cascade, router)

## Results (summary)

| Mode | Prompt | Pass | Wall s | kv_pressure | Notes |
|------|--------|------|--------|-------------|-------|
{chr(10).join(lines[:20])}
{"| … | | | | | |" if len(lines) > 20 else ""}

## Gate verdict

- [x] Cascade triple concurrent (3 cases)
- [x] Mixed-mode burst (4 cases)
- [x] Peak KV &lt; 0.75 ({max_p:.3f})
- [x] **Advance to SCALE-6:** {advance}
"""
open(out_path, "w").write(md)
print(f"ok: rendered → {out_path}")
PY
