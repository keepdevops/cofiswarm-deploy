#!/usr/bin/env bash
# Sprint 42: verify installed LaunchAgent is loaded (optional unless LAUNCHD_REQUIRE=1).
set -euo pipefail
LABEL="com.cofiswarm.stack-up"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
DOMAIN="gui/$(id -u)"

if [[ ! -f "$PLIST" ]]; then
  if [[ "${LAUNCHD_REQUIRE:-}" == "1" ]]; then
    echo "fail: ${PLIST} missing (run make install-launchd)" >&2
    exit 1
  fi
  echo "ok: launchd live skip (not installed)"
  exit 0
fi

grep -qE 'make up|stack-up\.sh' "$PLIST" || {
  echo "fail: installed plist must invoke make up or stack-up.sh" >&2
  exit 1
}

if launchctl print "${DOMAIN}/${LABEL}" >/dev/null 2>&1; then
  echo "ok: launchd loaded ${LABEL}"
elif launchctl list 2>/dev/null | grep -q "${LABEL}"; then
  echo "ok: launchd listed ${LABEL}"
elif [[ "${LAUNCHD_REQUIRE:-}" == "1" ]]; then
  echo "fail: ${LABEL} plist present but not loaded (make install-launchd)" >&2
  exit 1
else
  echo "ok: launchd live skip (plist present, not loaded)"
fi
