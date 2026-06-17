#!/usr/bin/env bash
# Sprint 51: mode-sdk VERSION, annotated tag, mode-* require v0.1.0.
set -euo pipefail
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"
SDK="${REPOS}/cofiswarm-mode-sdk"
VERSION_FILE="${SDK}/VERSION"
TAG="${MODE_SDK_TAG:-v0.1.0}"

[[ -f "$VERSION_FILE" ]] || { echo "fail: missing ${VERSION_FILE}" >&2; exit 1; }
ver="$(tr -d '[:space:]' < "$VERSION_FILE")"
[[ "$ver" == "$TAG" ]] || { echo "fail: VERSION=${ver} expected ${TAG}" >&2; exit 1; }

git -C "$SDK" rev-parse "$TAG" >/dev/null 2>&1 || {
  echo "fail: cofiswarm-mode-sdk missing tag ${TAG} (run ./scripts/tag-mode-sdk.sh)" >&2
  exit 1
}
tag_sha="$(git -C "$SDK" rev-parse "$TAG^{commit}")"
head_sha="$(git -C "$SDK" rev-parse HEAD)"
if [[ "$tag_sha" != "$head_sha" ]]; then
  echo "fail: mode-sdk tag ${TAG} (${tag_sha:0:7}) != HEAD (${head_sha:0:7})" >&2
  exit 1
fi

for m in mode-flat mode-pipeline mode-cascade mode-router; do
  gomod="${REPOS}/cofiswarm-${m}/go.mod"
  grep -q "github.com/keepdevops/cofiswarm-mode-sdk ${TAG}" "$gomod" \
    || { echo "fail: cofiswarm-${m}/go.mod must require mode-sdk ${TAG}" >&2; exit 1; }
  if grep -q 'replace.*\.\.' "$gomod"; then
    echo "fail: cofiswarm-${m}/go.mod still has local ../ replace" >&2
    exit 1
  fi
done

export GOWORK="${REPOS}/go.work"
[[ -f "$GOWORK" ]] || { echo "fail: missing $GOWORK" >&2; exit 1; }
for m in mode-flat mode-pipeline mode-cascade mode-router; do
  (cd "${REPOS}/cofiswarm-${m}" && CGO_ENABLED=0 go build -o /dev/null "./cmd/cofiswarm-${m}") \
    && echo "ok: build cofiswarm-${m} @ ${TAG}"
done

if [[ "${MODE_SDK_REQUIRE_REMOTE:-}" == "1" ]]; then
  remote="$(git -C "$SDK" ls-remote --tags origin "refs/tags/${TAG}" 2>/dev/null | awk '{print $1}' | head -1)"
  [[ -n "$remote" ]] || { echo "fail: origin missing tag ${TAG} (git push --tags)" >&2; exit 1; }
  echo "ok: remote tag ${TAG} (${remote:0:7})"
fi

echo "ok: mode-sdk release gate"
