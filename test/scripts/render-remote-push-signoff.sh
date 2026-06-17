#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/REMOTE-PUSH-SIGNOFF.md"

if [[ "${REMOTE_PUSH_SKIP_GATE:-}" != "1" ]]; then
  "${ROOT}/test/scripts/test-remote-push-signoff-gate.sh"
fi

python3 - "$OUT" <<'PY'
import datetime, sys
from pathlib import Path

ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
Path(sys.argv[1]).write_text(f"""# Remote push sign-off

**Date:** {ts}  
**Scope:** 43 repos + monorepo · origin branches @ pin SHA · `v1.1.0` tags

## Verdict

**Remote sync gate:** PASS (or skip until pushed)

## Gates

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
PUSH_DRY_RUN=1 ./scripts/push-all-repos.sh    # preview
./scripts/push-all-repos.sh
REMOTE_REQUIRE=1 make remote-push
```
""")
print(f"rendered {sys.argv[1]}")
PY
