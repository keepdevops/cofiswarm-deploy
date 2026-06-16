#!/usr/bin/env bash
# Configure service gate — health + MATRIX_LLAMA_SERVER path.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a
if [[ -n "${MATRIX_LLAMA_SERVER:-}" ]]; then
  MATRIX_LLAMA_SERVER="${MATRIX_LLAMA_SERVER/#\~/$HOME}"
fi
CFG="${CONFIGURE_URL:-http://127.0.0.1:8017}"

curl -sf --max-time 5 "${CFG}/healthz" >/dev/null || {
  echo "fail: configure not reachable at ${CFG} (make up)" >&2
  exit 1
}

if [[ -n "${MATRIX_LLAMA_SERVER:-}" && -x "${MATRIX_LLAMA_SERVER}" ]]; then
  echo "ok: configure up; MATRIX_LLAMA_SERVER=${MATRIX_LLAMA_SERVER}"
  exit 0
fi

if bin="$("${ROOT}/scripts/detect-llama-server.sh" 2>/dev/null)"; then
  echo "ok: configure up; suggest MATRIX_LLAMA_SERVER=${bin}"
  exit 0
fi

echo "fail: set MATRIX_LLAMA_SERVER in ${ROOT}/.env (see .env.example)" >&2
exit 1
