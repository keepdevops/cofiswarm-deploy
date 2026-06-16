#!/usr/bin/env bash
set -euo pipefail
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
CFG_REPO="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}/cofiswarm-config"
install -d "${FHS}/etc/cofiswarm/config/agents"
cp -R "${CFG_REPO}/agents/." "${FHS}/etc/cofiswarm/config/agents/"
cp "${CFG_REPO}/coordinator.json" "${FHS}/etc/cofiswarm/config/"
python3 "${CFG_REPO}/scripts/build_swarm_config.py" -o "${FHS}/etc/cofiswarm/config/swarm-config.json"
echo "rendered → ${FHS}/etc/cofiswarm/config/"
