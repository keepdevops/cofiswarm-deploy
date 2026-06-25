#!/usr/bin/env bash
# Install the LaunchAgent that runs the broker-free responder presence announcer at login
# (KeepAlive — a long-running re-announce loop). Mirrors install-host-inference-launchd.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a
DEPLOY="${ROOT}"
AGENTS="${HOME}/Library/LaunchAgents"
PLIST="${AGENTS}/com.cofiswarm.announcer.plist"
mkdir -p "${HOME}/Library/Logs/cofiswarm" "$AGENTS"
sed -e "s|\${HOME}|${HOME}|g" \
    -e "s|\${COFISWARM_DEPLOY:-\$HOME/cofiswarm/repos/cofiswarm-deploy}|${DEPLOY}|g" \
    "${ROOT}/deploy/launchd/com.cofiswarm.announcer.plist.template" >"$PLIST"
launchctl bootout "gui/$(id -u)/com.cofiswarm.announcer" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "ok: installed $PLIST (responder announcer at login)"
