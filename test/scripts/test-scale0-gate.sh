#!/usr/bin/env bash
# SCALE-0 gate (option-B topology, FHS-free): canonical repo config + compose config validate.
# Replaces the retired FHS/profile-16gb checks — config now lives in the repos and the stack is
# the observability plane (stack.yml) + the launcher control plane with the option-B overlay.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPOS="${COFISWARM_REPOS_ROOT:-$(cd "$ROOT/.." && pwd)}"
REPOS="${REPOS/#\~/$HOME}"
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a
export COFISWARM_REPOS_ROOT="$REPOS"

# 1. Canonical roster config lives in the repos (no FHS render step).
SWARM="${REPOS}/cofiswarm-config/swarm-config.json"
[[ -f "$SWARM" ]] || { echo "missing repo swarm-config: $SWARM" >&2; exit 1; }
python3 -c "import json,sys; d=json.load(open('$SWARM')); assert d.get('agents'), 'no agents'" \
  || { echo "swarm-config.json invalid or empty" >&2; exit 1; }
echo "ok: repo swarm-config.json valid"

# 2. Observability plane (stack.yml) — FHS-free; just needs COFISWARM_REPOS_ROOT.
docker compose -f "${ROOT}/compose/stack.yml" config >/dev/null \
  || { echo "stack.yml compose config invalid" >&2; exit 1; }
echo "ok: stack.yml config valid (no FHS)"

# 3. Option-B control plane: launcher compose + the host-infer overlay validate together.
LAUNCHER="${COFISWARM_LAUNCHER_COMPOSE:-${REPOS}/cofiswarm-launcher/compose}"
OVERRIDE="${ROOT}/compose/dispatch-host-infer.override.yml"
if [[ -f "${LAUNCHER}/docker-compose.yml" && -f "$OVERRIDE" ]]; then
  docker compose -f "${LAUNCHER}/docker-compose.yml" -f "$OVERRIDE" config >/dev/null \
    || { echo "launcher + option-B override compose config invalid" >&2; exit 1; }
  echo "ok: launcher + option-B override config valid"
else
  echo "skip: launcher compose / override not present"
fi

# 4. Best-effort pressure probe (slot-manager), non-fatal.
if curl -sf --max-time 2 http://127.0.0.1:8013/api/pressure >/dev/null 2>&1; then
  echo "pressure: slot-manager :8013"
else
  echo "pressure: skip (no service)"
fi

echo "ok: SCALE-0 gate — repo config + compose valid (option-B, FHS-free)"
