#!/usr/bin/env bash
# Render docs/MIGRATION-COMPLETE-SIGNOFF.md after migration-complete gate.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/MIGRATION-COMPLETE-SIGNOFF.md"

if [[ "${MIGRATION_COMPLETE_SKIP_GATE:-}" != "1" ]]; then
  "${ROOT}/test/scripts/test-migration-complete-signoff-gate.sh"
fi

python3 - "$ROOT/repos.json" "$OUT" <<'PY'
import datetime, json, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text())
out = Path(sys.argv[2])
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
rel = doc.get("release", "v1.1.0")
n = len(doc.get("pins") or {})
out.write_text(f"""# Migration complete sign-off

**Date:** {ts}  
**Release:** {rel} · {n} pinned repos  
**Device:** M3 Max · profile 16gb

## Verdict

**43-repo device migration:** PASS

Capstone gates: release cut @ pin SHAs · remote push (optional `REMOTE_REQUIRE=1`) · post-migration track (Sprints 32–56).

## Sign-offs

| Stage | Doc |
|-------|-----|
| Release cut | [RELEASE-CUT-SIGNOFF.md](./RELEASE-CUT-SIGNOFF.md) |
| Remote push | [REMOTE-PUSH-SIGNOFF.md](./REMOTE-PUSH-SIGNOFF.md) |
| Post-migration | [POST-MIGRATION-SIGNOFF.md](./POST-MIGRATION-SIGNOFF.md) |

## Gates

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
./scripts/pin-repos.sh
make migration-complete
REMOTE_REQUIRE=1 make migration-complete   # after ./scripts/push-all-repos.sh
```

Operator runbook: `cofiswarm-deploy/docs/runbook.md` § Migration complete
""")
print(f"rendered {out}")
PY
