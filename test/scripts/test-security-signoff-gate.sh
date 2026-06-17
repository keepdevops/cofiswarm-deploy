#!/usr/bin/env bash
# Sprint 43: UI dependency security sign-off.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

"${ROOT}/test/scripts/test-ui-security-gate.sh"
echo "ok: security signoff"
