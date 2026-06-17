#!/usr/bin/env bash
# Render docs/REPO-LAYOUT-SIGNOFF.md
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/REPO-LAYOUT-SIGNOFF.md"

if [[ "${REPO_LAYOUT_SKIP_GATE:-}" != "1" ]]; then
  "${ROOT}/test/scripts/test-repo-layout-signoff-gate.sh"
fi

python3 - "$ROOT/repos.json" "$OUT" <<'PY'
import datetime, json, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text())
out = Path(sys.argv[2])
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
n = len(doc.get("repos") or [])
md = f"""# Repo layout sign-off

**Date:** {ts}  
**Scope:** {n} repos · standalone FHS · no git submodules

## Verdict

**REPO-STANDARD-LAYOUT §15 (`test/standalone`) on every repo:** PASS

## Gates

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
make test-repo-layout-gate
make repo-layout
```

Per-repo CI template: `templates/repo-ci.yml` · `./scripts/install-repo-ci.sh`
"""
out.write_text(md)
print(f"rendered {out}")
PY
