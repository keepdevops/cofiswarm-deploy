#!/usr/bin/env bash
# Sprint 35: post-SCALE migration ops sign-off — stack health + UI ops + launchd.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
"${ROOT}/test/scripts/test-launchd-gate.sh"
"${ROOT}/test/scripts/test-stack-health-gate.sh"
"${ROOT}/test/scripts/test-ui-ops-gate.sh"
echo "ok: migration ops signoff"
