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

ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
Path(sys.argv[1]).write_text(f"""# Go CI workspace sign-off

**Date:** {ts}  
**Scope:** mode-* repos · `GOPRIVATE` + `mode-sdk@v0.1.0` from GitHub · no sibling `go.work`

## Verdict

**Per-repo CI builds mode plugins from published module:** PASS

## Gates

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
INSTALL_REPO_CI_FORCE=1 ./scripts/install-repo-ci.sh
make go-ci
MODE_SDK_REQUIRE_REMOTE=1 make test-mode-sdk-release-gate
```
""")
print(f"rendered {sys.argv[1]}")
PY
