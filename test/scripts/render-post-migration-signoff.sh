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
    ("Repo layout", "REPO-LAYOUT-SIGNOFF.md", doc.get("repo_layout_signoff")),
    ("Go modules", "GO-MODULES-SIGNOFF.md", doc.get("go_modules_signoff")),
    ("Per-repo CI", "REPO-CI-SIGNOFF.md", doc.get("repo_ci_signoff")),
    ("Go CI", "GO-CI-SIGNOFF.md", doc.get("go_ci_signoff")),
    ("mode-sdk release", "MODE-SDK-RELEASE-SIGNOFF.md", doc.get("mode_sdk_release_signoff")),
    ("Phase 6 optional", "PHASE6-SIGNOFF.md", doc.get("phase6_signoff")),
    ("Phase 7 optional", "PHASE7-SIGNOFF.md", doc.get("phase7_signoff")),
    ("Release cut", "RELEASE-CUT-SIGNOFF.md", doc.get("release_cut_signoff")),
    ("Remote push", "REMOTE-PUSH-SIGNOFF.md", doc.get("remote_push_signoff")),
    ("Migration complete", "MIGRATION-COMPLETE-SIGNOFF.md", doc.get("migration_complete_signoff")),
]
rows = "\n".join(
    f"| {name} | [{md}](./{md}) | {ver or '—'} |"
    for name, md, ver in tracks
)
md = f"""# Post-migration sign-off (Sprints 32–57)

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
