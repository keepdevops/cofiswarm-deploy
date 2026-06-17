#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
"${ROOT}/test/scripts/test-go-workspace-gate.sh"
echo "ok: go modules signoff"
