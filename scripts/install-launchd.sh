#!/usr/bin/env bash
# Install LaunchAgent to run cofiswarm stack-up at login.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
DEPLOY="${ROOT}"
AGENTS="${HOME}/Library/LaunchAgents"
PLIST="${AGENTS}/com.cofiswarm.stack-up.plist"
mkdir -p "${FHS}/var/log/cofiswarm" "$AGENTS"
sed -e "s|\${HOME}|${HOME}|g" \
    -e "s|\${COFISWARM_DEPLOY:-\$HOME/cofiswarm/repos/cofiswarm-deploy}|${DEPLOY}|g" \
    "${ROOT}/deploy/launchd/com.cofiswarm.stack-up.plist.template" >"$PLIST"
launchctl bootout "gui/$(id -u)/com.cofiswarm.stack-up" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "ok: installed $PLIST (stack-up at login)"
