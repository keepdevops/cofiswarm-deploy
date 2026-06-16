#!/usr/bin/env bash
# Render SCALE-2.md from scale2-workload.json.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
MONO="${MONO/#\~/$HOME}"
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${MONO}/docs/sprints/SCALE-2.md"
WORKLOAD="${FHS}/var/lib/cofiswarm/deploy/scale2-workload.json"

"${ROOT}/test/scripts/test-scale2-signoff-gate.sh"

python3 - "$WORKLOAD" "$OUT" <<'PY'
import json, sys
wpath, out_path = sys.argv[1:3]
w = json.load(open(wpath))
ts = w.get("ts", "")
rows = w.get("results", [])
peaks = [r["kv_pressure"] for r in rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
lines = []
for r in rows:
    kv = r.get("kv_pressure")
    kv_s = f"{kv:.3f}" if isinstance(kv, (int, float)) else "—"
    wall = r.get("wall_s")
    wall_s = str(wall) if wall is not None else "—"
    pass_s = "yes" if r.get("pass") else "no"
    lines.append(f"| {r.get('mode')} | {r.get('prompt')} | {pass_s} | {wall_s} | {kv_s} | {r.get('notes','')} |")
advance = "YES" if max_p < 0.60 else "NO (WARN peak kv)"
md = f"""# SCALE-2 — Long-context load sprint

**Date:** {ts}  
**Hardware:** M3 Max 36 GB  
**Roster:** 13 agents (load sprint)  
**Change:** P3 long-context + concurrent flat; `mode_config` passthrough.

## Commands

```bash
export COFISWARM_MODE_EXECUTE_TIMEOUT=600
make test-scale2-gate
make test-scale2-signoff-gate
```

Artifact: `scale2-workload.json` · peak kv **{max_p:.3f}**

## Results

| Mode | Prompt | Pass | Wall s | kv_pressure | Notes |
|------|--------|------|--------|-------------|-------|
{chr(10).join(lines)}

## Gate verdict

- [x] P3 + baseline workload logged
- [x] Peak KV &lt; 0.75 ({max_p:.3f})
- [x] **Advance to SCALE-3:** {advance}
"""
open(out_path, "w").write(md)
print(f"ok: rendered → {out_path}")
PY
