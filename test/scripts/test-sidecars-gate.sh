#!/usr/bin/env bash
# Sprint 45: convert :8015 + rag-worker :8018 in stack.
set -euo pipefail
HOST="${COFISWARM_SERVICE_HOST:-127.0.0.1}"

curl -sf --max-time 5 "http://${HOST}:8015/healthz" >/dev/null || {
  echo "fail: convert :8015 (run make build-convert && make up)" >&2
  exit 1
}
echo "ok: convert :8015"

curl -sf --max-time 5 "http://${HOST}:8018/healthz" >/dev/null || {
  echo "fail: rag-worker :8018" >&2
  exit 1
}
echo "ok: rag-worker :8018"

J=$(curl -sf --max-time 10 -X POST "http://${HOST}:8015/api/models/convert" \
  -H 'Content-Type: application/json' \
  -d '{"hf_repo":"test/model","output_name":"gate-demo"}')
echo "$J" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('job_id'); print('ok: convert job enqueue')"
