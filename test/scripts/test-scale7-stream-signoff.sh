#!/usr/bin/env bash
# Run all four architect stream gates (SCALE-7 stream coverage).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for g in \
  test-architect-stream-gate \
  test-architect-stream-pipeline-gate \
  test-architect-stream-router-gate \
  test-architect-stream-cascade-gate; do
  echo "==> $g"
  "${ROOT}/test/scripts/${g}.sh"
done
echo "ok: SCALE-7 stream signoff — flat, pipeline, router, cascade"
