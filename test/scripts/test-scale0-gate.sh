#!/usr/bin/env bash
# SCALE-0 gate: FHS layout + render-config + compose config validate.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a

for d in \
  "${FHS}/etc/cofiswarm/config" \
  "${FHS}/var/lib/cofiswarm/dispatch/sessions" \
  "${FHS}/var/lib/cofiswarm/models" \
  "${FHS}/var/log/cofiswarm" \
  "${FHS}/run/cofiswarm"; do
  [[ -d "$d" ]] || { echo "missing FHS dir: $d"; exit 1; }
done

for f in swarm-config.json coordinator.json; do
  [[ -f "${FHS}/etc/cofiswarm/config/${f}" ]] || { echo "missing ${f}"; exit 1; }
done

"${ROOT}/scripts/render-config.sh"

export COFISWARM_FHS_ROOT="$FHS"
PROFILE="${COFISWARM_PROFILE:-16gb}"
docker compose -f "${ROOT}/compose/stack.yml" \
  -f "${ROOT}/compose/profiles/${PROFILE}.yml" \
  --profile "$PROFILE" config >/dev/null

# Best-effort pressure probe (coordinator legacy or slot-manager)
if curl -sf --max-time 2 http://127.0.0.1:8013/api/pressure >/dev/null; then
  echo "pressure: slot-manager :8013"
elif curl -sf --max-time 2 http://127.0.0.1:8000/api/pressure >/dev/null; then
  echo "pressure: coordinator legacy :8000"
else
  echo "pressure: skip (no service)"
fi

date -u +"%Y-%m-%dT%H:%MZ" > "${FHS}/var/lib/cofiswarm/deploy/scale0.completed"
echo "ok: SCALE-0 gate — FHS wired, render-config, compose valid"
