#!/usr/bin/env bash
# Sprint 57: capstone — release-cut + remote-push + post-migration tracks.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"

"${ROOT}/test/scripts/test-release-cut-signoff-gate.sh"
"${ROOT}/test/scripts/test-remote-push-signoff-gate.sh"
"${ROOT}/test/scripts/test-post-migration-signoff-gate.sh"

for f in RELEASE-CUT-SIGNOFF.md REMOTE-PUSH-SIGNOFF.md POST-MIGRATION-SIGNOFF.md; do
  [[ -f "${MONO}/docs/${f}" ]] || { echo "fail: missing ${MONO}/docs/${f}" >&2; exit 1; }
  echo "ok: ${f}"
done

echo "ok: migration complete signoff"
