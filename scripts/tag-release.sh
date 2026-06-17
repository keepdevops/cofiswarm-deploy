#!/usr/bin/env bash
# Annotated git tags for v1.1.0 release (local; push with git push --tags).
set -euo pipefail
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
DEPLOY="${REPOS}/cofiswarm-deploy"
TAG="${RELEASE_TAG:-v1.1.0}"
MONO_TAG="${MONOREPO_RELEASE_TAG:-v1.1.0-migration}"

for repo in cofiswarm-deploy cofiswarm-observer cofiswarm-ui cofiswarm-grafana cofiswarm-common cofiswarm-gateway; do
  git -C "${REPOS}/${repo}" tag -a "${TAG}" -m "Cofiswarm ${TAG} device release." 2>/dev/null \
    && echo "tagged ${repo} ${TAG}" \
    || echo "skip: ${repo} ${TAG} (exists or error)"
done

git -C "$MONO" tag -a "${MONO_TAG}" -m "Cofiswarm monorepo ${TAG} migration + observability sign-off." 2>/dev/null \
  && echo "tagged cofiswarmdev ${MONO_TAG}" \
  || echo "skip: cofiswarmdev ${MONO_TAG}"

echo "ok: release tags (push: git push origin ${TAG} per repo; mono ${MONO_TAG})"
