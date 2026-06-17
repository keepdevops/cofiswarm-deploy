#!/usr/bin/env bash
# Sprint 41: verify v1.1.0 release tags on deploy + monorepo.
set -euo pipefail
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
TAG="${RELEASE_TAG:-v1.1.0}"
MONO_TAG="${MONOREPO_RELEASE_TAG:-v1.1.0-migration}"

git -C "${REPOS}/cofiswarm-deploy" rev-parse "${TAG}" >/dev/null 2>&1 || {
  echo "fail: cofiswarm-deploy missing tag ${TAG} (run ./scripts/tag-release.sh)" >&2
  exit 1
}
git -C "$MONO" rev-parse "${MONO_TAG}" >/dev/null 2>&1 || {
  echo "fail: cofiswarmdev missing tag ${MONO_TAG}" >&2
  exit 1
}
echo "ok: release tags ${TAG} (deploy) + ${MONO_TAG} (mono)"
