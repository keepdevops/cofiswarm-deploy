#!/usr/bin/env bash
# Sprint 43: cofiswarm-ui npm audit — no high/critical; overrides pinned.
set -euo pipefail
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"
UI="${REPOS}/cofiswarm-ui"
PKG="${UI}/package.json"

[[ -f "$PKG" ]] || { echo "fail: missing $PKG" >&2; exit 1; }

for dep in form-data js-yaml ws; do
  grep -q "\"${dep}\"" "$PKG" || {
    echo "fail: package.json missing override ${dep}" >&2
    exit 1
  }
done

cd "$UI"
npm audit --audit-level=high >/dev/null
echo "ok: ui npm audit (no high/critical)"
