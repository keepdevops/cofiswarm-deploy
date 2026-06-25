#!/usr/bin/env bash
# Install the LaunchAgent that starts the host llama/MLX inference servers at login
# (reboot survival). `make install-launchd` runs this alongside install-announcer-launchd.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a
DEPLOY="${ROOT}"
AGENTS="${HOME}/Library/LaunchAgents"
PLIST="${AGENTS}/com.cofiswarm.host-inference.plist"
mkdir -p "${HOME}/Library/Logs/cofiswarm" "$AGENTS"
sed -e "s|\${HOME}|${HOME}|g" \
    -e "s|\${COFISWARM_DEPLOY:-\$HOME/cofiswarm/repos/cofiswarm-deploy}|${DEPLOY}|g" \
    "${ROOT}/deploy/launchd/com.cofiswarm.host-inference.plist.template" >"$PLIST"
launchctl bootout "gui/$(id -u)/com.cofiswarm.host-inference" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "ok: installed $PLIST (host inference at login)"
