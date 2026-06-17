#!/usr/bin/env bash
# Sprint 58: hard remote sync — origin branches + tags must match pins.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"

REMOTE_REQUIRE=1 "${ROOT}/test/scripts/test-remote-sync-gate.sh"

for f in MIGRATION-COMPLETE-SIGNOFF.md REMOTE-PUSH-SIGNOFF.md; do
  [[ -f "${MONO}/docs/${f}" ]] || { echo "fail: missing ${MONO}/docs/${f}" >&2; exit 1; }
  echo "ok: ${f}"
done

echo "ok: remote complete signoff"
