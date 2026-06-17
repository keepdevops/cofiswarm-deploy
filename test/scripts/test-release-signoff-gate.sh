#!/usr/bin/env bash
# Sprint 40: v1.1.0 release gate — pins + signoff artifacts + ops smoke.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"

"${ROOT}/test/scripts/test-repos-pins-gate.sh"
for f in \
  "${MONO}/docs/MIGRATION-SIGNOFF.md" \
  "${MONO}/docs/MIGRATION-SCALE-SIGNOFF.md" \
  "${MONO}/docs/OBSERVABILITY-SIGNOFF.md"; do
  [[ -f "$f" ]] || { echo "fail: missing $f" >&2; exit 1; }
  echo "ok: $(basename "$f")"
done

"${ROOT}/test/scripts/test-migration-ops-gate.sh"
echo "ok: release signoff gate v1.1.0"
