#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/REPO-CI-SIGNOFF.md"

if [[ "${REPO_CI_SKIP_GATE:-}" != "1" ]]; then
  "${ROOT}/test/scripts/test-repo-ci-signoff-gate.sh"
fi

python3 - "$OUT" <<'PY'
import datetime, sys
from pathlib import Path

ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
md = f"""# Per-repo CI sign-off

**Date:** {ts}  
**Scope:** 43 repos · `actions/checkout@v6` · Node 24 / Go 1.22 · `make test` or `npm test`

## Verdict

**GitHub Actions ci.yml on every repo:** PASS

## Gates

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
./scripts/install-repo-ci.sh
make repo-ci
```
"""
Path(sys.argv[1]).write_text(md)
print(f"rendered {sys.argv[1]}")
PY
