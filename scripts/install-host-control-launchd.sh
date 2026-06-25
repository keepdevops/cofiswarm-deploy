#!/usr/bin/env bash
# Install the LaunchAgent that starts the host control-plane sidecars (configure + orchestrate)
# at login. `make install-launchd` runs this with the other host-side installers.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a
DEPLOY="${ROOT}"
AGENTS="${HOME}/Library/LaunchAgents"
PLIST="${AGENTS}/com.cofiswarm.host-control.plist"
mkdir -p "${HOME}/Library/Logs/cofiswarm" "$AGENTS"
sed -e "s|\${HOME}|${HOME}|g" \
    -e "s|\${COFISWARM_DEPLOY:-\$HOME/cofiswarm/repos/cofiswarm-deploy}|${DEPLOY}|g" \
    "${ROOT}/deploy/launchd/com.cofiswarm.host-control.plist.template" >"$PLIST"
launchctl bootout "gui/$(id -u)/com.cofiswarm.host-control" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "ok: installed $PLIST (host control sidecars at login)"
