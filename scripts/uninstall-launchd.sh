#!/usr/bin/env bash
# Remove the cofiswarm host-side LaunchAgents (host-inference + announcer).
set -euo pipefail
for LABEL in com.cofiswarm.host-inference com.cofiswarm.host-inference-watchdog com.cofiswarm.announcer com.cofiswarm.host-rag com.cofiswarm.host-control; do
  PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
  launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
  [[ -f "$PLIST" ]] && rm -f "$PLIST"
  echo "ok: uninstalled ${LABEL}"
done
