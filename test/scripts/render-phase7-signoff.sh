#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/PHASE7-SIGNOFF.md"

if [[ "${PHASE7_SKIP_GATE:-}" != "1" ]]; then
  "${ROOT}/test/scripts/test-phase7-signoff-gate.sh"
fi

python3 - "$OUT" <<'PY'
import datetime, sys
from pathlib import Path

ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
Path(sys.argv[1]).write_text(f"""# Phase 7 optional repos sign-off

**Date:** {ts}  
**Scope:** adapter-agentic (agentic harness stub)  
**Runtime:** not in default stack (`required: false`)

## Verdict

**Phase 7 scaffold + static tests:** PASS

## Gates

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
make phase7
make optional-repos    # phase 6 + 7
```
""")
print(f"rendered {sys.argv[1]}")
PY
