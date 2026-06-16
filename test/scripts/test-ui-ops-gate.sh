#!/usr/bin/env bash
# Sprint 34: combined UI ops gate — cleanup audit + API + stream smoke.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
"${ROOT}/test/scripts/test-gateway-cleanup-gate.sh"
"${ROOT}/test/scripts/test-ui-api-gate.sh"
"${ROOT}/test/scripts/test-ui-stream-gate.sh"
echo "ok: ui ops gate"
