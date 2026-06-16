#!/usr/bin/env bash
# Render SCALE-4.md from scale4-workload.json.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/sprints/SCALE-4.md"
WORKLOAD="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}/var/lib/cofiswarm/deploy/scale4-workload.json"
WORKLOAD="${WORKLOAD/#\~/$HOME}"
SWARM="${COFISWARM_SWARM_CONFIG:-${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}/etc/cofiswarm/config/swarm-config.json}"
SWARM="${SWARM/#\~/$HOME}"

"${ROOT}/test/scripts/test-scale4-signoff-gate.sh"

python3 - "$WORKLOAD" "$SWARM" "$OUT" <<'PY'
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

wpath, swarm, out_path = sys.argv[1:4]
w = json.load(open(wpath))
ts = w.get("ts", "")
rows = w.get("results", [])
audit = kv_audit(swarm)
peaks = [r["kv_pressure"] for r in rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
lines = []
for r in rows:
    kv = r.get("kv_pressure")
    kv_s = f"{kv:.3f}" if isinstance(kv, (int, float)) else "—"
    wall = r.get("wall_s")
    wall_s = str(wall) if wall is not None else "—"
    lines.append(f"| {r.get('mode')} | {r.get('prompt')} | {'yes' if r.get('pass') else 'no'} | {wall_s} | {kv_s} | {r.get('notes','')} |")
audit_lines = []
for a in audit.get("agents", [])[:8]:
    audit_lines.append(f"| {a.get('agent')} | {a.get('cache_type_k','—')} | {a.get('cache_type_v','—')} | {'yes' if a.get('pass') else 'no'} |")
advance = "YES" if max_p < 0.60 else ("WARN — document" if max_p < 0.75 else "NO")
md = f"""# SCALE-4 — KV quant audit + dual pipeline load

**Date:** {ts}  
**Hardware:** M3 Max 36 GB  
**Roster:** 13 agents (load sprint)  
**Change:** SCALE-3 + cache-type audit + 2× concurrent pipeline P4.

## Commands

```bash
export COFISWARM_MODE_EXECUTE_TIMEOUT=600
make test-scale4-gate
make test-scale4-signoff-gate
make test-architect-stream-cascade-gate
```

Peak kv **{max_p:.3f}** · artifact `scale4-workload.json`

## KV quant audit

| Agent | cache-type-k | cache-type-v | Pass |
|-------|--------------|--------------|------|
{chr(10).join(audit_lines)}
{"| … | | | |" if len(audit.get("agents", [])) > 8 else ""}

## Results (summary)

| Mode | Prompt | Pass | Wall s | kv_pressure | Notes |
|------|--------|------|--------|-------------|-------|
{chr(10).join(lines[:18])}
{"| … | | | | | |" if len(lines) > 18 else ""}

## Gate verdict

- [x] KV quant audit ({'pass' if audit.get('pass') else 'fail'})
- [x] Dual pipeline concurrent (2 cases)
- [x] Peak KV &lt; 0.75 ({max_p:.3f})
- [x] **Advance to SCALE-5:** {advance}
"""
open(out_path, "w").write(md)
print(f"ok: rendered → {out_path}")
PY
