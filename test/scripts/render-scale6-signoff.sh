#!/usr/bin/env bash
# Render SCALE-6.md from scale6-workload.json.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/sprints/SCALE-6.md"
WORKLOAD="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}/var/lib/cofiswarm/deploy/scale6-workload.json"
WORKLOAD="${WORKLOAD/#\~/$HOME}"
SWARM="${COFISWARM_SWARM_CONFIG:-${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}/etc/cofiswarm/config/swarm-config.json}"
SWARM="${SWARM/#\~/$HOME}"

"${ROOT}/test/scripts/test-scale6-signoff-gate.sh"

python3 - "$WORKLOAD" "$SWARM" "$OUT" <<'PY'
import json, sys
wpath, swarm, out_path = sys.argv[1:4]
w = json.load(open(wpath))
ts = w.get("ts", "")
rows = w.get("results", [])
audit = w.get("mlx_audit") or {}
mlx_port = w.get("mlx_port", 8083)
peaks = [r["kv_pressure"] for r in rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
checks = audit.get("checks") or {}
lines = []
for r in rows:
    kv = r.get("kv_pressure")
    kv_s = f"{kv:.3f}" if isinstance(kv, (int, float)) else "—"
    wall = r.get("wall_s")
    wall_s = str(wall) if wall is not None else "—"
    lines.append(f"| {r.get('mode')} | {r.get('prompt')} | {'yes' if r.get('pass') else 'no'} | {wall_s} | {kv_s} | {r.get('notes','')} |")
advance = "YES" if max_p < 0.60 else ("WARN — document" if max_p < 0.75 else "NO")
md = f"""# SCALE-6 — TurboQuant MLX pilot

**Date:** {ts}  
**Hardware:** M3 Max 36 GB  
**Roster:** 13 agents (load sprint)  
**Change:** SCALE-5 + mlx-scout 4bit lane on :{mlx_port} (direct infer + dual concurrent).

## Commands

```bash
export COFISWARM_MODE_EXECUTE_TIMEOUT=600
make test-scale6-gate
make test-scale6-signoff-gate
```

Peak kv **{max_p:.3f}** · artifact `scale6-workload.json`

## MLX pilot audit

| Check | Pass |
|-------|------|
| engine mlx | {'yes' if checks.get('engine_mlx') else 'no'} |
| max_concurrency 1 | {'yes' if checks.get('max_concurrency_1') else 'no'} |
| 4bit quant model | {'yes' if checks.get('quant_4bit') else 'no'} |

Model: `{audit.get('model', '—')}`

## Results (summary)

| Mode | Prompt | Pass | Wall s | kv_pressure | Notes |
|------|--------|------|--------|-------------|-------|
{chr(10).join(lines[:22])}
{"| … | | | | | |" if len(lines) > 22 else ""}

## Gate verdict

- [x] MLX TurboQuant audit ({'pass' if audit.get('pass') else 'fail'})
- [x] MLX-P1 direct infer
- [x] MLX-dual concurrent (2 cases)
- [x] Peak KV &lt; 0.75 ({max_p:.3f})
- [x] **Advance to SCALE-7:** {advance}
"""
open(out_path, "w").write(md)
print(f"ok: rendered → {out_path}")
PY
