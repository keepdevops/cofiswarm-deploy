#!/usr/bin/env bash
# Launch the host control-plane sidecars the :3000 UI proxies to (host.docker.internal),
# idempotent (port-binding guard). Reboot survival: com.cofiswarm.host-control LaunchAgent.
#   :8017  cofiswarm-configure  (configure API — UI /api/configure)
#   :3003  orch-sidecar         (MLX orchestrate — UI /api/orchestrate)
set -uo pipefail

BIN_DIR="${COFISWARM_BIN_DIR:-/Users/Shared/cofiswarm/bin}"
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
BASE="${COFISWARM_VAR_LIB:-$HOME/.local/share/cofiswarm}"
CFG_ROOT="${COFISWARM_CONFIG_ROOT:-$REPOS/cofiswarm-config/config}"
MODELS="${MATRIX_MODEL_DIR:-/Users/Shared/llama/models}"
BRIDGE="${COFISWARM_BRIDGE_URL:-http://127.0.0.1:5555}"
LOGDIR="${COFISWARM_INFER_LOGDIR:-$HOME/Library/Logs/cofiswarm}"
mkdir -p "$BIN_DIR" "$BASE" "$LOGDIR"

bound() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

# Rebuild the Go binaries if missing.
[[ -x "$BIN_DIR/cofiswarm-configure" ]] || \
  ( cd "$REPOS/cofiswarm-launcher" && GOWORK=off go build -o "$BIN_DIR/cofiswarm-configure" ./cmd/cofiswarm-configure ) \
  || { echo "FAIL: cofiswarm-configure build" >&2; exit 1; }
[[ -x "$BIN_DIR/orch-sidecar" ]] || \
  ( cd "$REPOS/cofiswarm-orchestrate" && GOWORK=off go build -o "$BIN_DIR/orch-sidecar" ./cmd/orch-sidecar ) \
  || { echo "FAIL: orch-sidecar build" >&2; exit 1; }

# 1. configure API (:8017) — state under VAR_LIB; bridge presence (announces "launcher").
if bound 8017; then echo "ok: configure :8017 already bound"
else
  COFISWARM_VAR_LIB="$BASE" COFISWARM_BRIDGE_URL="$BRIDGE" \
    nohup "$BIN_DIR/cofiswarm-configure" -listen :8017 >>"$LOGDIR/configure-8017.log" 2>&1 &
  echo "started: configure :8017 pid $!"
fi

# 2. orch-sidecar (:3003) — agents from COFISWARM_CONFIG_ROOT/agents, model-path expansion via
#    MATRIX_MODEL_DIR; bridge presence (announces "orchestrate").
if bound 3003; then echo "ok: orchestrate :3003 already bound"
else
  COFISWARM_CONFIG_ROOT="$CFG_ROOT" MATRIX_MODEL_DIR="$MODELS" COFISWARM_BRIDGE_URL="$BRIDGE" \
    ORCH_SIDECAR_PORT=3003 \
    nohup "$BIN_DIR/orch-sidecar" >>"$LOGDIR/orch-3003.log" 2>&1 &
  echo "started: orchestrate :3003 pid $!"
fi

echo "host-control launch dispatched (logs in $LOGDIR)"
