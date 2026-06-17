#!/usr/bin/env bash
# Sprint 44: CI-safe static gates (no make up / no pin drift).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"

echo "==> shell syntax"
for s in "${ROOT}/test/scripts/"*.sh; do bash -n "$s"; done
for s in "${ROOT}/scripts/"*.sh; do bash -n "$s"; done

"${ROOT}/test/scripts/test-repos-schema-gate.sh"
"${ROOT}/test/scripts/test-launchd-gate.sh"
make -C "$ROOT" test-standalone-layout
make -C "$ROOT" compose-config

if [[ -d "${REPOS}/cofiswarm-grafana" ]]; then
  "${ROOT}/test/scripts/test-grafana-layout-gate.sh"
else
  echo "skip: cofiswarm-grafana"
fi

if [[ -d "${REPOS}/cofiswarm-common" && -d "${REPOS}/cofiswarm-ui" && -d "${REPOS}/cofiswarm-gateway" ]]; then
  "${ROOT}/test/scripts/test-gateway-cleanup-gate.sh"
else
  echo "skip: gateway cleanup (sibling repos missing)"
fi

if [[ -f "${REPOS}/cofiswarm-ui/package.json" ]]; then
  echo "==> ui npm audit"
  (cd "${REPOS}/cofiswarm-ui" && npm ci)
  "${ROOT}/test/scripts/test-ui-security-gate.sh"
fi

if [[ -x "${REPOS}/cofiswarm-e2e/test/scripts/test-e2e-gate.sh" ]]; then
  "${REPOS}/cofiswarm-e2e/test/scripts/test-e2e-gate.sh"
fi

echo "ok: ci static gate"
