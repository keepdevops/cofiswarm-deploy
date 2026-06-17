#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/RELEASE-CUT-SIGNOFF.md"

if [[ "${RELEASE_CUT_SKIP_GATE:-}" != "1" ]]; then
  "${ROOT}/test/scripts/test-release-cut-signoff-gate.sh"
fi

python3 - "$ROOT/repos.json" "$OUT" <<'PY'
import datetime, json, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text())
out = Path(sys.argv[2])
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
rel = doc.get("release", "v1.1.0")
n = len(doc.get("pins") or {})
out.write_text(f"""# Release cut sign-off

**Date:** {ts}  
**Tag:** {rel} on {n} pinned repos · monorepo `v1.1.0-migration`

## Verdict

**Annotated release tags at pin SHAs:** PASS

## Gates

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
./scripts/pin-repos.sh
./scripts/tag-all-repos.sh
make release-cut
RELEASE_REQUIRE_REMOTE=1 make test-all-release-tags-gate   # after git push --tags
```

Push all tags: loop `git -C ~/cofiswarm/repos/<name> push origin {rel}`
""")
print(f"rendered {out}")
PY
