#!/usr/bin/env bash
# Remove cofiswarm stack-up LaunchAgent.
set -euo pipefail
LABEL="com.cofiswarm.stack-up"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
[[ -f "$PLIST" ]] && rm -f "$PLIST"
echo "ok: uninstalled ${LABEL}"
