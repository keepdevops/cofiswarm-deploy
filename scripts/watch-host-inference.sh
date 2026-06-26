#!/usr/bin/env bash
# Health-watchdog for the host llama/MLX inference servers (8083-8087). A server can crash on its
# own (observed: 8086 coder7b logged "cleaning up before exit") and the RunAtLoad host-inference
# LaunchAgent will NOT restart it — so a dead backend silently drops every agent it serves.
#
# Detection, in order of reliability:
#   1. Port not LISTEN-bound  -> the process exited (the real crash mode) -> dead. Instant, no
#      false positives. Applies to ALL ports including MLX.
#   2. Bound but /v1/models fails twice -> wedged/hung -> kill the listener so it frees, dead.
#      ONLY for the fast llama ports (HTTP_PORTS): MLX's /v1/models legitimately takes ~10s, so
#      HTTP-probing it would false-flag and kill a healthy MLX every cycle.
# Any dead port is respawned by the idempotent start-host-inference.sh (it skips bound ports, so
# an all-healthy run is a no-op). An mkdir lock prevents the 60s LaunchAgent timer from racing a
# manual run (which double-spawned MLX during testing). Driven by
# com.cofiswarm.host-inference-watchdog (StartInterval 60s); also safe to run by hand.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PORTS="${COFISWARM_INFER_PORTS:-8083 8084 8085 8086 8087}"   # all: ensured bound
HTTP_PORTS="${COFISWARM_INFER_HTTP_PORTS:-8084 8085 8086 8087}"  # fast llama: hang-probed (no MLX 8083)
TIMEOUT="${COFISWARM_WATCHDOG_TIMEOUT:-5}"
LOGDIR="${COFISWARM_INFER_LOGDIR:-$HOME/Library/Logs/cofiswarm}"
LOCK="${TMPDIR:-/tmp}/cofiswarm-watchdog.lock"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/watchdog.log"
ts() { date '+%Y-%m-%dT%H:%M:%S'; }
note() { echo "$(ts) watchdog: $*" >>"$LOG"; }

# Single-flight: if a prior run is still working, skip this fire (lock auto-clears on exit).
if ! mkdir "$LOCK" 2>/dev/null; then note "another run holds the lock — skipping"; exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

bound()   { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }
healthy() { curl -fsS -o /dev/null -m "$TIMEOUT" "http://127.0.0.1:$1/v1/models" 2>/dev/null; }
in_set()  { case " $2 " in *" $1 "*) return 0;; *) return 1;; esac; }

dead=""
for p in $PORTS; do
  if ! bound "$p"; then                 # process gone — definitive crash, no HTTP needed
    note ":$p not bound -> dead (process exited)"
    dead="$dead $p"
    continue
  fi
  in_set "$p" "$HTTP_PORTS" || continue  # bound MLX etc. — bound is enough, don't HTTP-probe
  healthy "$p" && continue
  sleep 3                                # one retry — avoid acting on a momentary blip
  healthy "$p" && continue
  note ":$p bound but failed 2 HTTP probes -> hung"
  pids="$(lsof -nP -tiTCP:"$p" -sTCP:LISTEN 2>/dev/null || true)"
  if [ -n "$pids" ]; then
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null && note "killed hung :$p (pid $pids)"
    sleep 1
  fi
  dead="$dead $p"
done

if [ -n "$dead" ]; then
  note "restarting host inference (dead:$dead)"
  "$SELF_DIR/start-host-inference.sh" >>"$LOG" 2>&1
  note "restart dispatched"
fi
