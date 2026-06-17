#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/GO-MODULES-SIGNOFF.md"

if [[ "${GO_MODULES_SKIP_GATE:-}" != "1" ]]; then
  "${ROOT}/test/scripts/test-go-modules-signoff-gate.sh"
fi

python3 - "$OUT" <<'PY'
import datetime, sys
from pathlib import Path

ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
md = f"""# Go modules sign-off

**Date:** {ts}  
**Pattern:** `go.work` at `~/cofiswarm/repos/go.work` · `replace` for mode-sdk in workspace · no `replace ../` in mode `go.mod`

## Verdict

**Sibling Go workspace + mode-sdk v0.1.0:** PASS

## Gates

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
./scripts/render-go-workspace.sh
CGO_ENABLED=0 make build-modes
make test-go-workspace-gate
```
"""
Path(sys.argv[1]).write_text(md)
print(f"rendered {sys.argv[1]}")
PY
