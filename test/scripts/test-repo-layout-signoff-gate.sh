#!/usr/bin/env bash
# Sprint 47: repo layout sign-off.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
"${ROOT}/test/scripts/test-repo-layout-gate.sh"
echo "ok: repo layout signoff"
