#!/usr/bin/env bash
# Sprint 45: sidecar sign-off — convert + rag-worker.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

"${ROOT}/test/scripts/test-sidecars-gate.sh"
echo "ok: sidecars signoff"
