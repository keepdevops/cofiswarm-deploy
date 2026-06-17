#!/usr/bin/env bash
# Sprint 35: static launchd ops gate — plist template + install script.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEMPLATE="${ROOT}/deploy/launchd/com.cofiswarm.stack-up.plist.template"
INSTALL="${ROOT}/scripts/install-launchd.sh"
UNINSTALL="${ROOT}/scripts/uninstall-launchd.sh"
RENDERED="$(mktemp)"
trap 'rm -f "$RENDERED"' EXIT

[[ -x "$INSTALL" ]] || { echo "fail: missing $INSTALL" >&2; exit 1; }
[[ -x "$UNINSTALL" ]] || { echo "fail: missing $UNINSTALL" >&2; exit 1; }
grep -q bootout "$UNINSTALL" || { echo "fail: uninstall must bootout agent" >&2; exit 1; }
[[ -f "$TEMPLATE" ]] || { echo "fail: missing $TEMPLATE" >&2; exit 1; }

grep -q 'stack-up.sh\|make up' "$TEMPLATE" || {
  echo "fail: launchd template must invoke stack-up or make up" >&2
  exit 1
}
grep -q 'com.cofiswarm.stack-up' "$TEMPLATE" || {
  echo "fail: launchd label missing" >&2
  exit 1
}

sed -e "s|\${HOME}|${HOME}|g" \
    -e "s|\${COFISWARM_DEPLOY:-\$HOME/cofiswarm/repos/cofiswarm-deploy}|${ROOT}|g" \
    "$TEMPLATE" >"$RENDERED"

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$RENDERED" >/dev/null || { echo "fail: plist lint" >&2; exit 1; }
  echo "ok: launchd plist lint"
else
  grep -q '<plist' "$RENDERED" || { echo "fail: invalid plist" >&2; exit 1; }
  echo "ok: launchd plist structure (plutil unavailable)"
fi

echo "ok: launchd ops gate"
