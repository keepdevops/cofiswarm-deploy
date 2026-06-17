#!/usr/bin/env bash
# Sprint 42: device ops sign-off — stack health, UI ops, launchd static + live.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

"${ROOT}/test/scripts/test-migration-ops-gate.sh"
"${ROOT}/test/scripts/test-launchd-live-gate.sh"
echo "ok: device ops signoff"
