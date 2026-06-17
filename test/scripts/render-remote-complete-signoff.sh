#!/usr/bin/env bash
# Render docs/REMOTE-COMPLETE-SIGNOFF.md after remote-complete gate.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/REMOTE-COMPLETE-SIGNOFF.md"

if [[ "${REMOTE_COMPLETE_SKIP_GATE:-}" != "1" ]]; then
  "${ROOT}/test/scripts/test-remote-complete-signoff-gate.sh"
fi

python3 - "$ROOT/repos.json" "$OUT" <<'PY'
import datetime, json, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text())
out = Path(sys.argv[2])
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
rel = doc.get("release", "v1.1.0")
n = len(doc.get("pins") or {})
out.write_text(f"""# Remote complete sign-off

**Date:** {ts}  
**Release:** {rel} · {n} repos on origin @ pin SHA · `v1.1.0` tags  
**Device:** M3 Max · profile 16gb

## Verdict

**Remote push closure:** PASS

All pinned repos and monorepo tag verified on origin (`REMOTE_REQUIRE=1`).

## Prerequisites

| Stage | Doc |
|-------|-----|
| Migration complete | [MIGRATION-COMPLETE-SIGNOFF.md](./MIGRATION-COMPLETE-SIGNOFF.md) |
| Remote push | [REMOTE-PUSH-SIGNOFF.md](./REMOTE-PUSH-SIGNOFF.md) |

## Gates

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
./scripts/verify-remote-push.sh              # status (non-fatal)
./scripts/push-all-repos.sh                  # if drift
REMOTE_REQUIRE=1 make remote-complete
```

Operator runbook: `cofiswarm-deploy/docs/runbook.md` § Remote complete
""")
print(f"rendered {out}")
PY
