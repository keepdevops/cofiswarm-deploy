#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
"${ROOT}/test/scripts/test-mode-sdk-release-gate.sh"
echo "ok: mode-sdk release signoff"
