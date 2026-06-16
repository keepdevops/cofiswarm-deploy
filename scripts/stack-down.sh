#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ -f .env ]] && set -a && source .env && set +a
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
PROFILE="${COFISWARM_PROFILE:-16gb}"
RUN="${FHS}/run/cofiswarm"

for pidf in "${RUN}"/*.pid; do
  [[ -f "$pidf" ]] || continue
  pid=$(cat "$pidf")
  kill "$pid" 2>/dev/null && echo "stopped pid=$pid" || true
  rm -f "$pidf"
done

export COFISWARM_FHS_ROOT="$FHS"
docker compose -f compose/stack.yml -f "compose/profiles/${PROFILE}.yml" --profile "$PROFILE" down
echo "stack down"
