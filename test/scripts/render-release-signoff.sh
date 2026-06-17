#!/usr/bin/env bash
# Render docs/DEVICE-RELEASE-SIGNOFF.md — migration + observability + SCALE.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/DEVICE-RELEASE-SIGNOFF.md"

"${ROOT}/test/scripts/test-release-signoff-gate.sh"

python3 - "$ROOT/repos.json" "$OUT" <<'PY'
import datetime, json, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text())
out = Path(sys.argv[2])
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
rel = doc.get("release", "v1.1.0")
md = f"""# Device release sign-off

**Date:** {ts}  
**Release:** {rel}  
**Device:** M3 Max · profile 16gb

## Verdict

**Migration + SCALE-7 + UI ops + observability:** PASS

## Sign-offs

| Track | Doc |
|-------|-----|
| Migration structure | [MIGRATION-SIGNOFF.md](./MIGRATION-SIGNOFF.md) |
| SCALE 0–7 | [MIGRATION-SCALE-SIGNOFF.md](./MIGRATION-SCALE-SIGNOFF.md) |
| Observability | [OBSERVABILITY-SIGNOFF.md](./OBSERVABILITY-SIGNOFF.md) |

## Gates

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
./scripts/pin-repos.sh
make test-release-signoff-gate
```

Pins: `{len(doc.get("pins") or {})}` repos · `migration_signoff={doc.get("migration_signoff")}` · `observability_signoff={doc.get("observability_signoff")}`
"""
out.write_text(md)
print(f"rendered {out}")
PY
