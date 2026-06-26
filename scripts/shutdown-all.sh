#!/usr/bin/env bash
#
# shutdown-all.sh — stop EVERYTHING for cofiswarm in one shot.
#
#   * docker compose stack (via the active profile)
#   * any stray cofiswarm-* containers not owned by that profile
#   * host-side binaries under /Users/Shared/cofiswarm/bin (and $FHS bin)
#   * pid-tracked processes + loose helper scripts (announce-responders.sh, ...)
#
# Loud by design: every action is logged, failures are reported, never silent.
#
# Host processes are managed by launchd (KeepAlive), so they are stopped via
# `launchctl bootout` — a plain kill loses to KeepAlive and the job respawns.
#
# Usage:
#   ./scripts/shutdown-all.sh            # stop containers + launchd jobs + strays
#   ./scripts/shutdown-all.sh --dry-run  # show what would be stopped, change nothing
#   ./scripts/shutdown-all.sh --force    # SIGKILL anything still alive after grace
#   ./scripts/shutdown-all.sh --disable  # also `launchctl disable` so jobs stay
#                                        # down across logout/reboot
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ -f .env ]] && set -a && source .env && set +a

FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
PROFILE="${COFISWARM_PROFILE:-16gb}"
RUN="${FHS}/run/cofiswarm"
SHARED_BIN="/Users/Shared/cofiswarm/bin"

LAUNCHD_PREFIX="${COFISWARM_LAUNCHD_PREFIX:-com.cofiswarm.}"
GUI_DOMAIN="gui/$(id -u)"

DRY_RUN=0
FORCE=0
DISABLE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --force)   FORCE=1 ;;
    --disable) DISABLE=1 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown argument: $arg" >&2; exit 2 ;;
  esac
done

log()  { echo "[shutdown-all] $*"; }
warn() { echo "[shutdown-all] WARN: $*" >&2; }
err()  { echo "[shutdown-all] ERROR: $*" >&2; }

# run CMD..., honouring --dry-run; logs and tolerates failure (returns 0).
do_run() {
  if (( DRY_RUN )); then
    log "DRY-RUN would: $*"
    return 0
  fi
  if ! "$@"; then
    warn "command failed (continuing): $*"
    return 1
  fi
}

# --- 1. pid files tracked by the stack ------------------------------------
stop_pidfiles() {
  shopt -s nullglob
  local pidf pid found=0
  for pidf in "${RUN}"/*.pid; do
    found=1
    pid="$(cat "$pidf" 2>/dev/null || true)"
    if [[ -z "$pid" ]]; then
      warn "empty pid file: $pidf"
      do_run rm -f "$pidf"
      continue
    fi
    if kill -0 "$pid" 2>/dev/null; then
      log "stopping pid=$pid (from $(basename "$pidf"))"
      do_run kill "$pid"
    else
      log "pid=$pid already dead (from $(basename "$pidf"))"
    fi
    do_run rm -f "$pidf"
  done
  shopt -u nullglob
  (( found )) || log "no pid files in ${RUN}"
}

# --- 1b. launchd jobs (the supervisors that respawn host processes) -------
# Must run BEFORE killing host processes: bootout removes the job (stopping
# its KeepAlive respawn) and sends SIGTERM to the running instance.
stop_launchd() {
  if ! command -v launchctl >/dev/null 2>&1; then
    warn "launchctl not found; skipping launchd teardown"
    return 0
  fi
  local labels
  labels="$(launchctl list 2>/dev/null | awk -v p="$LAUNCHD_PREFIX" \
    'index($3, p) == 1 {print $3}' || true)"
  if [[ -z "$labels" ]]; then
    log "no launchd jobs matching ${LAUNCHD_PREFIX}*"
    return 0
  fi
  log "launchd jobs matching ${LAUNCHD_PREFIX}*:"
  echo "$labels" | sed 's/^/    /'
  while IFS= read -r label; do
    [[ -z "$label" ]] && continue
    do_run launchctl bootout "${GUI_DOMAIN}/${label}"
    if (( DISABLE )); then
      do_run launchctl disable "${GUI_DOMAIN}/${label}"
    fi
  done <<< "$labels"
}

# --- 2. docker compose stack ----------------------------------------------
stop_compose() {
  if ! command -v docker >/dev/null 2>&1; then
    warn "docker not found; skipping compose teardown"
    return 0
  fi
  local profile_yml="compose/profiles/${PROFILE}.yml"
  if [[ ! -f compose/stack.yml ]]; then
    warn "compose/stack.yml not found; skipping compose teardown"
    return 0
  fi
  export COFISWARM_FHS_ROOT="$FHS"
  log "docker compose down (profile=${PROFILE})"
  if [[ -f "$profile_yml" ]]; then
    do_run docker compose -f compose/stack.yml -f "$profile_yml" \
      --profile "$PROFILE" down --remove-orphans
  else
    warn "profile file $profile_yml missing; downing base stack only"
    do_run docker compose -f compose/stack.yml down --remove-orphans
  fi
}

# --- 3. any remaining cofiswarm-* containers ------------------------------
stop_stray_containers() {
  command -v docker >/dev/null 2>&1 || return 0
  local names
  names="$(docker ps -a --filter 'name=cofiswarm' --format '{{.Names}}' 2>/dev/null || true)"
  if [[ -z "$names" ]]; then
    log "no stray cofiswarm-* containers"
    return 0
  fi
  log "stray cofiswarm-* containers remain:"
  echo "$names" | sed 's/^/    /'
  while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    do_run docker rm -f "$c"
  done <<< "$names"
}

# --- 4. host-side binaries + loose helper scripts -------------------------
# Matches the cofiswarm bin dir and known helper scripts, but never this
# script or the user's editors/shell.
stop_host_processes() {
  local pattern="${SHARED_BIN}|${FHS}/bin/cofiswarm|announce-responders\\.sh|orch-sidecar"
  local pids
  pids="$(pgrep -f "$pattern" 2>/dev/null | grep -v "^$$\$" || true)"
  if [[ -z "$pids" ]]; then
    log "no host-side cofiswarm processes running"
    return 0
  fi
  log "host-side cofiswarm processes:"
  ps -o pid=,command= -p $(echo "$pids" | tr '\n' ' ') 2>/dev/null | sed 's/^/    /'
  for pid in $pids; do
    do_run kill "$pid"
  done

  # grace period, then optional hard kill of survivors
  (( DRY_RUN )) && return 0
  sleep 2
  local survivors
  survivors="$(pgrep -f "$pattern" 2>/dev/null | grep -v "^$$\$" || true)"
  if [[ -n "$survivors" ]]; then
    if (( FORCE )); then
      warn "force-killing survivors: $(echo "$survivors" | tr '\n' ' ')"
      for pid in $survivors; do do_run kill -9 "$pid"; done
    else
      warn "still alive after SIGTERM (re-run with --force to SIGKILL):"
      ps -o pid=,command= -p $(echo "$survivors" | tr '\n' ' ') 2>/dev/null | sed 's/^/    /'
    fi
  fi
}

main() {
  (( DRY_RUN )) && log "DRY-RUN: no processes or containers will be changed"
  log "FHS=$FHS  PROFILE=$PROFILE"
  stop_launchd
  stop_pidfiles
  stop_compose
  stop_stray_containers
  stop_host_processes
  log "shutdown-all complete"
}

main
