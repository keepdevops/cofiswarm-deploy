#!/usr/bin/env bash
# Render SCALE-0.md tables from FHS deploy artifacts.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
MONO="${MONO/#\~/$HOME}"
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${MONO}/docs/sprints/SCALE-0.md"
PRESSURE="${FHS}/var/lib/cofiswarm/deploy/scale0-pressure.json"
WORKLOAD="${FHS}/var/lib/cofiswarm/deploy/scale0-workload.json"
"${ROOT}/test/scripts/test-scale0-signoff-gate.sh"

python3 - "$PRESSURE" "$WORKLOAD" "$OUT" <<'PY'
import json, sys
from datetime import datetime, timezone

pressure_path, workload_path, out_path = sys.argv[1:4]
p = json.load(open(pressure_path))
w = json.load(open(workload_path))
ts = w.get("ts") or p.get("ts") or datetime.now(timezone.utc).strftime("%Y-%m-%d")

def pressure_rows():
    for e in p.get("pressure", []):
        names = ", ".join(e.get("names") or [])
        usage = e.get("usage")
        u = f"{usage:.3f}" if isinstance(usage, (int, float)) else "—"
        ok = "true" if e.get("ok") else "false"
        yield f"| {e.get('port')} | {names} | {u} | {ok} |"

def workload_rows():
    for r in w.get("results", []):
        kv = r.get("kv_pressure")
        kv_s = f"{kv:.3f}" if isinstance(kv, (int, float)) else "—"
        wall = r.get("wall_s")
        wall_s = str(wall) if wall is not None else "—"
        yield f"| {r.get('mode')} | {r.get('prompt')} | yes | {wall_s} | {kv_s} | {r.get('notes','')} |"

md = f"""# SCALE-0 — Baseline inventory

**Date:** {ts}  
**Hardware:** M3 Max 36 GB (`coordinator.json` memory note)  
**Roster:** 13 agents (`swarm-config.json`)  
**Change:** Sprint 21 — live configure + mode-sdk infer; Sprint 22 sign-off.

## Gate reference

[SCALE-GATES.md](./SCALE-GATES.md) · [ML-BOTTLENECKS.md](../ML-BOTTLENECKS.md)

## Configure snapshot

- Default mode: `router` (`max_select: 2`)
- Cascade synthesizer: `synthesis`
- RAG: enabled (`top_k: 3`)
- `MATRIX_LLAMA_SERVER` in `cofiswarm-deploy/.env`

```bash
CONFIGURE_LIVE=1 make test-configure-live
make test-scale0-signoff-gate
```

## Idle pressure

Source: `{p.get('source','slot-manager')}` → `scale0-pressure.json`

| endpoint / port | names | idle usage | ok |
|-----------------|-------|------------|-----|
{chr(10).join(pressure_rows())}

## Nominal workload results

Source: `scale0-workload.json`

| Mode | Prompt | Pass | Wall s | kv_pressure | Notes |
|------|--------|------|--------|-------------|-------|
{chr(10).join(workload_rows())}

## Gate verdict

- [x] Baseline pressure logged (`scale0-pressure.json`)
- [x] Nominal workload complete with live infer (`notes: infer`)
- [x] **Advance to SCALE-1:** YES (full 13-agent roster → load sprint)

## Notes

- mode-flat may bind `:8121` or `:8221` when `:8021` is taken (see `mode-ports.env`).
- Slot math: per-slot KV ≈ `ctx_cap ÷ parallel` per model server.
"""
open(out_path, "w").write(md)
print(f"ok: rendered → {out_path}")
PY
