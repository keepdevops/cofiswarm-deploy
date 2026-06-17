#!/usr/bin/env bash
# Sprint 44: CI sign-off — static gates + optional device live gates.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

"${ROOT}/test/scripts/test-ci-static-gate.sh"

if [[ "${COFISWARM_CI_LIVE:-}" == "1" ]]; then
  echo "==> live device gates"
  "${ROOT}/test/scripts/test-repos-pins-gate.sh"
  "${ROOT}/test/scripts/test-stack-health-gate.sh"
fi

echo "ok: ci signoff"
