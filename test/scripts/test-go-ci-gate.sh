#!/usr/bin/env bash
# Sprint 52: mode-* CI uses GOPRIVATE + published mode-sdk v0.1.0 (no sibling go.work).
set -euo pipefail
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"

bad=()
for m in mode-flat mode-pipeline mode-cascade mode-router; do
  ci="${REPOS}/cofiswarm-${m}/.github/workflows/ci.yml"
  gomod="${REPOS}/cofiswarm-${m}/go.mod"
  if [[ ! -f "$ci" ]]; then
    bad+=("cofiswarm-${m}: missing ci.yml")
    continue
  fi
  grep -q 'GOPRIVATE: github.com/keepdevops/' "$ci" \
    || bad+=("cofiswarm-${m}: ci.yml missing GOPRIVATE")
  grep -q 'secrets.GITHUB_TOKEN' "$ci" \
    || bad+=("cofiswarm-${m}: ci.yml missing GITHUB_TOKEN git config")
  if grep -q 'cofiswarm-mode-sdk' "$ci" || grep -q 'go.work' "$ci"; then
    bad+=("cofiswarm-${m}: ci.yml must not use sibling mode-sdk checkout")
  fi
  grep -q 'github.com/keepdevops/cofiswarm-mode-sdk v0.1.0' "$gomod" \
    || bad+=("cofiswarm-${m}: go.mod must require mode-sdk v0.1.0")
done

if ((${#bad[@]})); then
  echo "fail: go ci" >&2
  printf '  %s\n' "${bad[@]}" >&2
  exit 1
fi

export GOPRIVATE=github.com/keepdevops/*
export GONOSUMDB=github.com/keepdevops/*
for m in mode-flat mode-pipeline mode-cascade mode-router; do
  (cd "${REPOS}/cofiswarm-${m}" && GOWORK=off CGO_ENABLED=0 go build -o /dev/null "./cmd/cofiswarm-${m}") \
    && echo "ok: published build cofiswarm-${m}"
done
echo "ok: go ci (4 mode repos, published module)"
