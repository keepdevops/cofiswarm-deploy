#!/usr/bin/env bash
# Sprint 48: go.work present; mode-* builds without ../ replace in go.mod.
set -euo pipefail
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"
GOWORK="${REPOS}/go.work"
GO="${GO:-go}"

[[ -f "$GOWORK" ]] || { echo "fail: missing $GOWORK (run ./scripts/render-go-workspace.sh)" >&2; exit 1; }
grep -q 'replace github.com/keepdevops/cofiswarm-mode-sdk => ./cofiswarm-mode-sdk' "$GOWORK" \
  || { echo "fail: go.work missing mode-sdk replace" >&2; exit 1; }

for m in mode-flat mode-pipeline mode-cascade mode-router; do
  gomod="${REPOS}/cofiswarm-${m}/go.mod"
  [[ -f "$gomod" ]] || { echo "fail: missing $gomod" >&2; exit 1; }
  if grep -q 'replace.*\.\.' "$gomod"; then
    echo "fail: cofiswarm-${m}/go.mod still has local ../ replace" >&2
    exit 1
  fi
done

export GOWORK
for m in mode-flat mode-pipeline mode-cascade mode-router; do
  (cd "${REPOS}/cofiswarm-${m}" && CGO_ENABLED=0 "$GO" build -o /dev/null ./cmd/cofiswarm-${m}) \
    && echo "ok: build cofiswarm-${m}"
done
echo "ok: go workspace gate"
