#!/usr/bin/env bash
# Push pinned SHAs + release tag to origin for all cofiswarm-* repos.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
TAG="${RELEASE_TAG:-v1.1.0}"
MONO_TAG="${MONOREPO_RELEASE_TAG:-v1.1.0-migration}"
DRY="${PUSH_DRY_RUN:-}"

push_one() {
  local name="$1" pin="$2"
  local path="${REPOS}/${name}"
  [[ -d "${path}/.git" ]] || { echo "skip: ${name} (no checkout)"; return 0; }
  local head branch
  head="$(git -C "$path" rev-parse HEAD)"
  branch="$(git -C "$path" rev-parse --abbrev-ref HEAD)"
  if [[ "$head" != "$pin" ]]; then
    echo "warn: ${name} HEAD ${head:0:8} != pin ${pin:0:8} (pushing HEAD anyway)" >&2
  fi
  if [[ -n "$DRY" ]]; then
    echo "dry-run: git -C ${path} push origin ${branch} && git -C ${path} push origin ${TAG}"
    return 0
  fi
  git -C "$path" push origin "${branch}"
  git -C "$path" push origin "${TAG}"
  echo "pushed: ${name} (${branch} + ${TAG})"
}

while IFS=$'\t' read -r name pin; do
  [[ -n "$name" && -n "$pin" ]] || continue
  push_one "$name" "$pin"
done < <(python3 - "$ROOT/repos.json" <<'PY'
import json, sys
from pathlib import Path
for name, pin in json.loads(Path(sys.argv[1]).read_text()).get("pins", {}).items():
    if pin:
        print(f"{name}\t{pin}")
PY
)

if [[ -n "$DRY" ]]; then
  echo "dry-run: git -C ${MONO} push origin $(git -C "$MONO" rev-parse --abbrev-ref HEAD) && git -C ${MONO} push origin ${MONO_TAG}"
else
  git -C "$MONO" push origin "$(git -C "$MONO" rev-parse --abbrev-ref HEAD)"
  git -C "$MONO" push origin "${MONO_TAG}" 2>/dev/null || true
  echo "pushed: cofiswarmdev ($(git -C "$MONO" rev-parse --abbrev-ref HEAD) + ${MONO_TAG})"
fi
echo "ok: push-all-repos"
