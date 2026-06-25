#!/usr/bin/env bash
# Print launchd install/load state for the cofiswarm host-side LaunchAgents.
set -euo pipefail
DOMAIN="gui/$(id -u)"
for LABEL in com.cofiswarm.host-inference com.cofiswarm.announcer; do
  PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
  echo "== ${LABEL} =="
  if [[ -f "$PLIST" ]]; then echo "  plist: $PLIST"; else echo "  plist: not installed"; fi
  if launchctl print "${DOMAIN}/${LABEL}" >/dev/null 2>&1; then
    echo "  state: loaded"
  elif launchctl list 2>/dev/null | grep -q "${LABEL}"; then
    echo "  state: listed"
  else
    echo "  state: not loaded"
  fi
done
