#!/usr/bin/env bash
# Static launchd ops gate — the host-side LaunchAgent templates (host-inference + announcer)
# plus their install scripts and the shared uninstall script. (Supersedes the retired stack-up
# LaunchAgent; the stack is brought up by scripts/start-stack.sh, not a launchd `make up`.)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UNINSTALL="${ROOT}/scripts/uninstall-launchd.sh"

[[ -x "$UNINSTALL" ]] || { echo "fail: missing $UNINSTALL" >&2; exit 1; }
grep -q bootout "$UNINSTALL" || { echo "fail: uninstall must bootout agents" >&2; exit 1; }

check_agent() { # label template install-script
  local label="$1" template="$2" install="$3"
  [[ -x "$install" ]] || { echo "fail: missing $install" >&2; exit 1; }
  [[ -f "$template" ]] || { echo "fail: missing $template" >&2; exit 1; }
  grep -q "$label" "$template" || { echo "fail: label $label missing in $template" >&2; exit 1; }
  local rendered; rendered="$(mktemp)"
  sed -e "s|\${HOME}|${HOME}|g" \
      -e "s|\${COFISWARM_DEPLOY:-\$HOME/cofiswarm/repos/cofiswarm-deploy}|${ROOT}|g" \
      "$template" >"$rendered"
  if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$rendered" >/dev/null || { echo "fail: plist lint $label" >&2; rm -f "$rendered"; exit 1; }
  else
    grep -q '<plist' "$rendered" || { echo "fail: invalid plist $label" >&2; rm -f "$rendered"; exit 1; }
  fi
  rm -f "$rendered"
  echo "ok: ${label} plist lint"
}

check_agent com.cofiswarm.host-inference \
  "${ROOT}/deploy/launchd/com.cofiswarm.host-inference.plist.template" \
  "${ROOT}/scripts/install-host-inference-launchd.sh"
check_agent com.cofiswarm.announcer \
  "${ROOT}/deploy/launchd/com.cofiswarm.announcer.plist.template" \
  "${ROOT}/scripts/install-announcer-launchd.sh"

echo "ok: launchd ops gate"
