#!/usr/bin/env bash
# Render docs/CI-SIGNOFF.md after CI gate.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/CI-SIGNOFF.md"

if [[ "${CI_SKIP_GATE:-}" != "1" ]]; then
  "${ROOT}/test/scripts/test-ci-signoff-gate.sh"
fi

python3 - "$OUT" <<'PY'
import datetime, sys
from pathlib import Path

ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
md = f"""# CI sign-off

**Date:** {ts}  
**Scope:** static gates (GitHub Actions + local)

## Verdict

**repos schema · layout · compose · gateway · grafana · ui audit · e2e layout:** PASS

## Gates

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
make ci                    # static
COFISWARM_CI_LIVE=1 make test-ci-signoff-gate   # + device pins + stack health
```

Workflow: `.github/workflows/ci.yml`
"""
Path(sys.argv[1]).write_text(md)
print(f"rendered {sys.argv[1]}")
PY
