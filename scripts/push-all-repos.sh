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
TAG_FORCE="${PUSH_TAG_FORCE:-}"

push_tag() {
  local path="$1" label="$2" tag="$3"
  local local_sha remote_sha
  if ! git -C "$path" rev-parse "${tag}^{commit}" >/dev/null 2>&1; then
    echo "skip: ${label} (no local tag ${tag})" >&2
    return 0
  fi
  local_sha="$(git -C "$path" rev-parse "${tag}^{commit}")"
  remote_sha="$(git -C "$path" ls-remote --tags origin "refs/tags/${tag}" 2>/dev/null | awk '{print $1}' | head -1)"
  if [[ -n "$remote_sha" && "$remote_sha" == "$local_sha" ]]; then
    echo "skip: ${label} ${tag} (already on origin @${local_sha:0:8})"
    return 0
  fi
  if [[ -n "$DRY" ]]; then
  if [[ -n "$remote_sha" && "$remote_sha" != "$local_sha" ]]; then
      echo "dry-run: git -C ${path} push origin ${tag} --force  # remote @${remote_sha:0:8}"
    else
      echo "dry-run: git -C ${path} push origin ${tag}"
    fi
    return 0
  fi
  if [[ -n "$remote_sha" && "$remote_sha" != "$local_sha" ]]; then
    if [[ -n "$TAG_FORCE" ]]; then
      git -C "$path" push origin "refs/tags/${tag}:refs/tags/${tag}" --force
      echo "pushed: ${label} ${tag} --force (@${local_sha:0:8})"
      return 0
    fi
    echo "fail: ${label} origin ${tag} @${remote_sha:0:8} != local @${local_sha:0:8}" >&2
    echo "  run: ./scripts/tag-all-repos.sh && PUSH_TAG_FORCE=1 ./scripts/push-all-repos.sh" >&2
    return 1
  fi
  git -C "$path" push origin "${tag}"
  echo "pushed: ${label} ${tag} (@${local_sha:0:8})"
}

push_one() {
  local name="$1" pin="$2"
  local path="${REPOS}/${name}"
  [[ -d "${path}/.git" ]] || { echo "skip: ${name} (no checkout)"; return 0; }
  local head branch
  head="$(git -C "$path" rev-parse HEAD)"
  branch="$(git -C "$path" rev-parse --abbrev-ref HEAD)"
  if [[ "$head" != "$pin" ]]; then
    if [[ "${PUSH_ALLOW_PIN_DRIFT:-}" == "1" ]]; then
      echo "warn: ${name} HEAD ${head:0:8} != pin ${pin:0:8} (pushing HEAD)" >&2
    else
      echo "fail: ${name} HEAD ${head:0:8} != pin ${pin:0:8}" >&2
      echo "  run: ./scripts/pin-repos.sh && git add repos.json && git commit" >&2
      return 1
    fi
  fi
  if [[ -n "$DRY" ]]; then
    echo "dry-run: git -C ${path} push origin ${branch}"
    push_tag "$path" "$name" "$TAG"
    return 0
  fi
  git -C "$path" push origin "${branch}"
  push_tag "$path" "$name" "$TAG"
  echo "pushed: ${name} (${branch})"
}

if [[ "${PUSH_SKIP_PIN_REPOS:-}" != "1" ]]; then
  "${ROOT}/scripts/pin-repos.sh"
fi

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
  echo "dry-run: git -C ${MONO} push origin $(git -C "$MONO" rev-parse --abbrev-ref HEAD)"
  push_tag "$MONO" "cofiswarmdev" "$MONO_TAG"
else
  git -C "$MONO" push origin "$(git -C "$MONO" rev-parse --abbrev-ref HEAD)"
  push_tag "$MONO" "cofiswarmdev" "$MONO_TAG"
  echo "pushed: cofiswarmdev ($(git -C "$MONO" rev-parse --abbrev-ref HEAD))"
fi
echo "ok: push-all-repos"
