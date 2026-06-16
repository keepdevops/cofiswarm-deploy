#!/usr/bin/env bash
# Sprint 36: render docs/MIGRATION-SIGNOFF.md after gates pass.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/MIGRATION-SIGNOFF.md"
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
SCALE7="${FHS}/var/lib/cofiswarm/deploy/scale7-workload.json"

"${ROOT}/test/scripts/test-migration-signoff-gate.sh"

python3 - "$ROOT/repos.json" "$SCALE7" "$OUT" <<'PY'
import json, datetime, sys
from pathlib import Path

repos_path, scale7_path, out_path = sys.argv[1:4]
doc = json.loads(Path(repos_path).read_text())
scale = json.loads(Path(scale7_path).read_text()) if Path(scale7_path).is_file() else {}
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
release = doc.get("release", "v1.1.0")
signoff = doc.get("migration_signoff", release)
roster = scale.get("roster") or {}
rows = scale.get("results") or []
peaks = [r["kv_pressure"] for r in rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
archived = [r["name"] for r in doc.get("repos", []) if r.get("status") == "archived"]

md = f"""# Cofiswarm migration sign-off

**Date:** {ts}  
**Release:** {release}  
**Device:** M3 Max · profile 16gb  

## Verdict

**Structure + SCALE + UI ops:** PASS  
**Migration sign-off:** YES (`{signoff}`)

## Gates

| Gate | Status |
|------|--------|
| SCALE-0 … SCALE-7 | PASS (see [MIGRATION-SCALE-SIGNOFF.md](./MIGRATION-SCALE-SIGNOFF.md)) |
| UI gateway :3000 → dispatch :8010 | PASS (Sprint 32–34) |
| `make test-migration-ops-gate` | PASS (Sprint 35) |
| `repos.json` pins | PASS (Sprint 36) |

## Scale summary

| Metric | Value |
|--------|-------|
| Workload cases | {len(rows)} |
| Peak KV | {max_p:.3f} |
| Roster llama | {len(roster.get('llama_ok') or [])}/{roster.get('llama_expected', '—')} |
| MLX scout | {'yes' if roster.get('mlx_ok') else 'no'} |

## Archived repos

{chr(10).join('- ' + a for a in archived)}

## Commands

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
make up
make test-migration-signoff-gate
./scripts/pin-repos.sh   # refresh pins after commits
```

Sprint docs: `docs/POST-MIGRATION-SPRINT-{{16..35}}.md`
"""
Path(out_path).write_text(md)
print(f"rendered {out_path}")
PY
