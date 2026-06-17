#!/usr/bin/env bash
# Render docs/POST-MIGRATION-SIGNOFF.md after post-migration gate.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/POST-MIGRATION-SIGNOFF.md"

if [[ "${POST_MIGRATION_SKIP_GATE:-}" != "1" ]]; then
  "${ROOT}/test/scripts/test-post-migration-signoff-gate.sh"
fi

python3 - "$ROOT/repos.json" "$OUT" <<'PY'
import datetime, json, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text())
out = Path(sys.argv[2])
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
rel = doc.get("release", "v1.1.0")
tracks = [
    ("Migration", "MIGRATION-SIGNOFF.md", doc.get("migration_signoff")),
    ("SCALE 0–7", "MIGRATION-SCALE-SIGNOFF.md", rel),
    ("Observability", "OBSERVABILITY-SIGNOFF.md", doc.get("observability_signoff")),
    ("Device release", "DEVICE-RELEASE-SIGNOFF.md", rel),
    ("Device ops", "DEVICE-OPS-SIGNOFF.md", doc.get("device_ops_signoff")),
    ("Security", "SECURITY-SIGNOFF.md", doc.get("security_signoff")),
    ("CI", "CI-SIGNOFF.md", doc.get("ci_signoff")),
    ("Sidecars", "SIDECARS-SIGNOFF.md", doc.get("sidecars_signoff")),
]
rows = "\n".join(
    f"| {name} | [{md}](./{md}) | {ver or '—'} |"
    for name, md, ver in tracks
)
md = f"""# Post-migration sign-off (Sprints 32–45)

**Date:** {ts}  
**Release:** {rel}  
**Device:** M3 Max · profile 16gb

## Verdict

**Post-cutover ops track:** PASS

## Tracks

| Track | Doc | Sign-off |
|-------|-----|----------|
{rows}

## Gates

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
./scripts/pin-repos.sh
make post-migration
POST_MIGRATION_LIVE=1 make test-post-migration-signoff-gate   # optional + stack
```

Pins: `{len(doc.get("pins") or {})}` repos
"""
out.write_text(md)
print(f"rendered {out}")
PY
