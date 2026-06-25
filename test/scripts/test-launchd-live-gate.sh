#!/usr/bin/env bash
# Verify the installed host-side LaunchAgents are loaded (optional unless LAUNCHD_REQUIRE=1).
# Supersedes the retired stack-up agent; checks host-inference + announcer.
set -euo pipefail
DOMAIN="gui/$(id -u)"
REQUIRE="${LAUNCHD_REQUIRE:-}"

check_live() { # label expect-invocation-substr
  local label="$1" want="$2"
  local plist="${HOME}/Library/LaunchAgents/${label}.plist"
  if [[ ! -f "$plist" ]]; then
    if [[ "$REQUIRE" == "1" ]]; then echo "fail: ${plist} missing (run make install-launchd)" >&2; exit 1; fi
    echo "ok: ${label} live skip (not installed)"; return 0
  fi
  grep -q "$want" "$plist" || { echo "fail: ${label} plist must invoke ${want}" >&2; exit 1; }
  if launchctl print "${DOMAIN}/${label}" >/dev/null 2>&1; then
    echo "ok: launchd loaded ${label}"
  elif launchctl list 2>/dev/null | grep -q "${label}"; then
    echo "ok: launchd listed ${label}"
  elif [[ "$REQUIRE" == "1" ]]; then
    echo "fail: ${label} present but not loaded — run: make install-launchd" >&2; exit 1
  else
    echo "ok: ${label} live skip (present, not loaded)"
  fi
}

check_live com.cofiswarm.host-inference start-host-inference.sh
check_live com.cofiswarm.announcer announce-responders.sh
check_live com.cofiswarm.host-rag start-host-rag.sh
check_live com.cofiswarm.host-control start-host-control.sh
