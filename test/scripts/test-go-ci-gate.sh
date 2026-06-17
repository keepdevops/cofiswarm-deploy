#!/usr/bin/env bash
# Sprint 50: mode-* ci.yml checks out mode-sdk and writes go.work for make test.
set -euo pipefail
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"

bad=()
for m in mode-flat mode-pipeline mode-cascade mode-router; do
  ci="${REPOS}/cofiswarm-${m}/.github/workflows/ci.yml"
  if [[ ! -f "$ci" ]]; then
    bad+=("cofiswarm-${m}: missing ci.yml")
    continue
  fi
  grep -q 'keepdevops/cofiswarm-mode-sdk' "$ci" \
    || bad+=("cofiswarm-${m}: ci.yml missing mode-sdk checkout")
  grep -q 'go.work' "$ci" \
    || bad+=("cofiswarm-${m}: ci.yml missing go.work step")
done

if ((${#bad[@]})); then
  echo "fail: go ci" >&2
  printf '  %s\n' "${bad[@]}" >&2
  exit 1
fi
echo "ok: go ci (4 mode repos)"
