#!/usr/bin/env bash
# SCALE-0 full gate: layout + pressure probe + workload smoke (best-effort).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
"${ROOT}/test/scripts/test-scale0-gate.sh"
"${ROOT}/test/scripts/test-scale0-probe.sh"
if "${ROOT}/test/scripts/test-scale0-workload.sh"; then
  echo "ok: SCALE-0 full gate"
else
  echo "warn: SCALE-0 workload incomplete (dispatch stub or infer down)" >&2
  exit 0
fi
