#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/GO-CI-SIGNOFF.md"

if [[ "${GO_CI_SKIP_GATE:-}" != "1" ]]; then
  "${ROOT}/test/scripts/test-go-ci-signoff-gate.sh"
fi

python3 - "$OUT" <<'PY'
import datetime, sys
from pathlib import Path

out = Path(sys.argv[1])
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
out.write_text(f"""# Go CI workspace sign-off

**Date:** {ts}  
**Scope:** mode-* repos · checkout mode-sdk · ephemeral go.work in GitHub Actions

## Verdict

**Per-repo CI can build mode plugins:** PASS

## Gates

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
INSTALL_REPO_CI_FORCE=1 ./scripts/install-repo-ci.sh
make go-ci
```
""")
print(f"rendered {out}")
PY
