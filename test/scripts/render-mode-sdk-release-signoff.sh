#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/MODE-SDK-RELEASE-SIGNOFF.md"

if [[ "${MODE_SDK_RELEASE_SKIP_GATE:-}" != "1" ]]; then
  "${ROOT}/test/scripts/test-mode-sdk-release-signoff-gate.sh"
fi

python3 - "$OUT" <<'PY'
import datetime, sys
from pathlib import Path

ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
Path(sys.argv[1]).write_text(f"""# mode-sdk release sign-off

**Date:** {ts}  
**Module:** `github.com/keepdevops/cofiswarm-mode-sdk` · **Tag:** v0.1.0

## Verdict

**Versioned mode-sdk + mode plugin requires:** PASS

## Gates

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
./scripts/tag-mode-sdk.sh
make mode-sdk-release
MODE_SDK_REQUIRE_REMOTE=1 make test-mode-sdk-release-gate   # after git push --tags
```

Push tag: `git -C ~/cofiswarm/repos/cofiswarm-mode-sdk push origin v0.1.0`
""")
print(f"rendered {sys.argv[1]}")
PY
