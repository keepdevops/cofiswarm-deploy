#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"
PROFILE="${COFISWARM_PROFILE:-16gb}"
CFG_REPO="${REPOS}/cofiswarm-config"

install -d "${FHS}/etc/cofiswarm/config/agents" \
         "${FHS}/etc/cofiswarm/profiles" \
         "${FHS}/var/lib/cofiswarm/dispatch/sessions" \
         "${FHS}/var/lib/cofiswarm/dispatch/history" \
         "${FHS}/var/lib/cofiswarm/rag/index" \
         "${FHS}/var/lib/cofiswarm/observer/plugins" \
         "${FHS}/var/log/cofiswarm/agent_logs" \
         "${FHS}/run/cofiswarm"

if [[ -d "${CFG_REPO}/config/agents" ]]; then
  cp -R "${CFG_REPO}/config/agents/." "${FHS}/etc/cofiswarm/config/agents/"
elif [[ -d "${CFG_REPO}/agents" ]]; then
  cp -R "${CFG_REPO}/agents/." "${FHS}/etc/cofiswarm/config/agents/"
fi
[[ -f "${CFG_REPO}/config/coordinator.json" ]] && \
  cp "${CFG_REPO}/config/coordinator.json" "${FHS}/etc/cofiswarm/config/"
[[ -f "${CFG_REPO}/coordinator.json" ]] && \
  cp "${CFG_REPO}/coordinator.json" "${FHS}/etc/cofiswarm/config/"

if [[ -f "${CFG_REPO}/scripts/build_swarm_config.py" ]]; then
  python3 "${CFG_REPO}/scripts/build_swarm_config.py" --root "${CFG_REPO}"
  cp "${CFG_REPO}/swarm-config.json" "${FHS}/etc/cofiswarm/config/swarm-config.json"
elif [[ -f "${FHS}/etc/cofiswarm/config/swarm-config.json" ]]; then
  echo "keep existing swarm-config.json"
else
  echo "warn: no cofiswarm-config build script" >&2
fi

if [[ -f "${ROOT}/config/profiles/${PROFILE}.env" ]]; then
  cp "${ROOT}/config/profiles/${PROFILE}.env" "${FHS}/etc/cofiswarm/profiles/active.env"
fi

# Mirror per-service configs from repos when present
for svc in slot-manager kvpool agent-registry dispatch mode-flat mode-pipeline mode-cascade mode-router; do
  src="${REPOS}/cofiswarm-${svc}/test/standalone/etc/cofiswarm/${svc}"
  [[ -d "$src" ]] && install -d "${FHS}/etc/cofiswarm/${svc}" && cp -R "${src}/." "${FHS}/etc/cofiswarm/${svc}/" 2>/dev/null || true
done

echo "rendered → ${FHS}/etc/cofiswarm/ (profile=${PROFILE})"
