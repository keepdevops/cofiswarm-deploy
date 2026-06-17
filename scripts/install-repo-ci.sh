#!/usr/bin/env bash
# Copy templates/repo-ci.yml into cofiswarm-* repos (skip if ci.yml exists).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"
TEMPLATE="${ROOT}/templates/repo-ci.yml"
[[ -f "$TEMPLATE" ]] || { echo "fail: missing $TEMPLATE" >&2; exit 1; }

install_one() {
  local name="$1"
  local dest="${REPOS}/${name}/.github/workflows/ci.yml"
  [[ -d "${REPOS}/${name}" ]] || { echo "skip: ${name} (no checkout)"; return 0; }
  if [[ -f "$dest" && "${INSTALL_REPO_CI_FORCE:-}" != "1" ]]; then
    echo "skip: ${name} (ci.yml exists)"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$TEMPLATE" "$dest"
  echo "installed: ${dest}"
}

if [[ $# -gt 0 ]]; then
  for name in "$@"; do install_one "$name"; done
else
  while IFS= read -r name; do
    install_one "$name"
  done < <(python3 - "$ROOT/repos.json" <<'PY'
import json, sys
from pathlib import Path
for r in json.loads(Path(sys.argv[1]).read_text()).get("repos") or []:
    print(r["name"])
PY
)
fi
echo "ok: install-repo-ci"
