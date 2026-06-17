#!/usr/bin/env bash
# Print launchd agent install/load state for cofiswarm stack-up.
set -euo pipefail
LABEL="com.cofiswarm.stack-up"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
DOMAIN="gui/$(id -u)"

if [[ -f "$PLIST" ]]; then
  echo "plist: $PLIST"
else
  echo "plist: not installed"
fi

if launchctl print "${DOMAIN}/${LABEL}" >/dev/null 2>&1; then
  echo "state: loaded"
elif launchctl list 2>/dev/null | grep -q "${LABEL}"; then
  echo "state: listed"
else
  echo "state: not loaded"
fi
