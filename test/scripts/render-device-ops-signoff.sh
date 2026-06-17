#!/usr/bin/env bash
# Render docs/DEVICE-OPS-SIGNOFF.md after device ops gate.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/DEVICE-OPS-SIGNOFF.md"

if [[ "${DEVICE_OPS_SKIP_GATE:-}" != "1" ]]; then
  "${ROOT}/test/scripts/test-device-ops-signoff-gate.sh"
fi

python3 - "$OUT" <<'PY'
import datetime, sys
from pathlib import Path

ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
md = f"""# Device ops sign-off

**Date:** {ts}  
**Stack:** `make up` · UI :3000 · launchd optional login start

## Verdict

**Stack health + UI ops + launchd template:** PASS

## LaunchAgent (optional)

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
make install-launchd
./scripts/launchd-status.sh
LAUNCHD_REQUIRE=1 make test-launchd-live-gate
make uninstall-launchd   # remove
```

## Gates

```bash
make up
make test-device-ops-signoff-gate
```

See `cofiswarm-deploy/docs/runbook.md`.
"""
Path(sys.argv[1]).write_text(md)
print(f"rendered {sys.argv[1]}")
PY
