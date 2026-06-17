#!/usr/bin/env bash
# Annotated git tag for cofiswarm-mode-sdk (reads VERSION file).
set -euo pipefail
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"
SDK="${REPOS}/cofiswarm-mode-sdk"
VERSION_FILE="${SDK}/VERSION"

[[ -f "$VERSION_FILE" ]] || { echo "fail: missing ${VERSION_FILE}" >&2; exit 1; }
TAG="$(tr -d '[:space:]' < "$VERSION_FILE")"
[[ "$TAG" == v* ]] || TAG="v${TAG}"

git -C "$SDK" tag -a "$TAG" -m "cofiswarm-mode-sdk ${TAG}." 2>/dev/null \
  && echo "tagged cofiswarm-mode-sdk ${TAG}" \
  || echo "skip: cofiswarm-mode-sdk ${TAG} (exists or error)"

echo "ok: mode-sdk tag (push: git -C ${SDK} push origin ${TAG})"
