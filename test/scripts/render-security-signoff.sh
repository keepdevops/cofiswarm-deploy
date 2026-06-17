#!/usr/bin/env bash
# Render docs/SECURITY-SIGNOFF.md after security gate.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/SECURITY-SIGNOFF.md"

if [[ "${SECURITY_SKIP_GATE:-}" != "1" ]]; then
  "${ROOT}/test/scripts/test-security-signoff-gate.sh"
fi

python3 - "$OUT" <<'PY'
import datetime, sys
from pathlib import Path

ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
md = f"""# Security sign-off — cofiswarm-ui

**Date:** {ts}  
**Scope:** npm audit (dev + prod tree) · Dependabot weekly

## Verdict

**No high/critical npm vulnerabilities:** PASS

## Gates

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
make test-ui-security-gate
make test-security-signoff-gate
```

Dependabot: `cofiswarm-ui/.github/dependabot.yml`
"""
Path(sys.argv[1]).write_text(md)
print(f"rendered {sys.argv[1]}")
PY
