#!/usr/bin/env bash
# Sprint 36: final migration sign-off — cutover + SCALE-7 + ops + pins.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
"${ROOT}/test/scripts/test-cutover-gate.sh"
"${ROOT}/test/scripts/test-scale7-signoff-gate.sh"
"${ROOT}/test/scripts/test-migration-ops-gate.sh"
"${ROOT}/test/scripts/test-repos-pins-gate.sh"
echo "ok: migration signoff gate"
