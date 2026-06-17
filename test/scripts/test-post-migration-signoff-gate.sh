#!/usr/bin/env bash
# Sprint 46+: post-migration track sign-off (Sprints 32–49 artifacts + pins).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"

for f in \
  MIGRATION-SIGNOFF.md \
  MIGRATION-SCALE-SIGNOFF.md \
  OBSERVABILITY-SIGNOFF.md \
  DEVICE-RELEASE-SIGNOFF.md \
  DEVICE-OPS-SIGNOFF.md \
  SECURITY-SIGNOFF.md \
  CI-SIGNOFF.md \
  SIDECARS-SIGNOFF.md \
  REPO-LAYOUT-SIGNOFF.md \
  GO-MODULES-SIGNOFF.md \
  REPO-CI-SIGNOFF.md \
  GO-CI-SIGNOFF.md \
  MODE-SDK-RELEASE-SIGNOFF.md \
  PHASE6-SIGNOFF.md \
  PHASE7-SIGNOFF.md; do
  [[ -f "${MONO}/docs/${f}" ]] || { echo "fail: missing ${MONO}/docs/${f}" >&2; exit 1; }
  echo "ok: ${f}"
done

"${ROOT}/test/scripts/test-repos-schema-gate.sh"
"${ROOT}/test/scripts/test-repos-pins-gate.sh"

if [[ "${POST_MIGRATION_LIVE:-}" == "1" ]]; then
  echo "==> live device gates"
  "${ROOT}/test/scripts/test-sidecars-signoff-gate.sh"
  "${ROOT}/test/scripts/test-device-ops-signoff-gate.sh"
fi

echo "ok: post-migration signoff"
