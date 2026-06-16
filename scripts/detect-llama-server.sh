#!/usr/bin/env bash
# Pick llama-server for MATRIX_LLAMA_SERVER (.env).
set -euo pipefail
for c in \
  "${MATRIX_LLAMA_SERVER:-}" \
  "${HOME}/llama.cpp/build/bin/llama-server" \
  "/Users/Shared/llama/llama.cpp-master/build/bin/llama-server" \
  "$(command -v llama-server 2>/dev/null || true)"; do
  [[ -n "$c" && -x "$c" ]] || continue
  echo "$c"
  exit 0
done
echo "fail: llama-server not found (brew/build or set MATRIX_LLAMA_SERVER)" >&2
exit 1
