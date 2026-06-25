#!/usr/bin/env bash
# Launch the host RAG services the option-B stack uses for per-agent RAG, all idempotent
# (port-binding guard, not flaky HTTP). Reboot survival: com.cofiswarm.host-rag LaunchAgent.
#   :8090  nomic embeddings server  (llama.cpp --embeddings, nomic-embed-text-v1.5)
#   :8001  cofiswarm-rag            (serverless sqlite-vec store, nomic embedder, non-FHS DB)
#   :8018  cofiswarm-rag-worker     (auto-index queue drain)
# dispatch reaches :8001 via host.docker.internal (see dispatch-host-infer.override.yml).
set -uo pipefail

LLAMA_BIN="${COFISWARM_LLAMA_SERVER:-/Users/Shared/llama/llama.cpp-master/build/bin/llama-server}"
NOMIC_MODEL="${COFISWARM_NOMIC_MODEL:-/Users/Shared/llama/models/embed/nomic-embed-text-v1.5.f16.gguf}"
BIN_DIR="${COFISWARM_BIN_DIR:-/Users/Shared/cofiswarm/bin}"
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
BASE="${COFISWARM_VAR_LIB:-$HOME/.local/share/cofiswarm}"
LOGDIR="${COFISWARM_INFER_LOGDIR:-$HOME/Library/Logs/cofiswarm}"
BRIDGE="${COFISWARM_BRIDGE_URL:-http://127.0.0.1:5555}"
NOMIC_URL="${NOMIC_EMBED_URL:-http://127.0.0.1:8090/v1/embeddings}"
mkdir -p "$BIN_DIR" "$BASE/rag/index/queue" "$LOGDIR"

bound() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

# Rebuild the Go binaries if missing (rag needs CGO for the sqlite-vec extension).
[[ -x "$BIN_DIR/cofiswarm-rag" ]] || \
  ( cd "$REPOS/cofiswarm-rag" && CGO_ENABLED=1 CC=cc GOWORK=off go build -o "$BIN_DIR/cofiswarm-rag" ./cmd/cofiswarm-rag ) \
  || { echo "FAIL: cofiswarm-rag build" >&2; exit 1; }
[[ -x "$BIN_DIR/cofiswarm-rag-worker" ]] || \
  ( cd "$REPOS/cofiswarm-rag-worker" && GOWORK=off go build -o "$BIN_DIR/cofiswarm-rag-worker" ./cmd/cofiswarm-rag-worker ) \
  || { echo "FAIL: cofiswarm-rag-worker build" >&2; exit 1; }

# 1. nomic embeddings server (:8090) — rag embeds queries/docs against this.
if bound 8090; then echo "ok: nomic-embed :8090 already bound"
elif [[ ! -f "$NOMIC_MODEL" ]]; then echo "FAIL: missing nomic model $NOMIC_MODEL" >&2
else
  # nomic-embed-text-v1.5 supports 2048 ctx; size the batch to match so multi-hundred-token
  # doc chunks fit in one physical batch (default 512 rejects chunks >512 tokens on ingest).
  nohup "$LLAMA_BIN" --embeddings -m "$NOMIC_MODEL" --host 127.0.0.1 --port 8090 -ngl 99 \
    -c 2048 -b 2048 -ub 2048 \
    >>"$LOGDIR/nomic-8090.log" 2>&1 &
  echo "started: nomic-embed :8090 pid $!"
fi

# 2. rag service (:8001) — serverless sqlite-vec, nomic embedder, non-FHS DB, bridge presence.
if bound 8001; then echo "ok: rag :8001 already bound"
else
  RAG_SQLITE_PATH="$BASE/rag/index/rag.db" RAG_INGEST_EMBEDDER=nomic \
    NOMIC_EMBED_URL="$NOMIC_URL" COFISWARM_BRIDGE_URL="$BRIDGE" RAG_INGEST_PORT=8001 \
    nohup "$BIN_DIR/cofiswarm-rag" >>"$LOGDIR/rag-8001.log" 2>&1 &
  echo "started: rag :8001 pid $!"
fi

# 3. rag-worker (:8018) — non-FHS auto-index queue, bridge presence.
if bound 8018; then echo "ok: rag-worker :8018 already bound"
else
  COFISWARM_VAR_LIB="$BASE" COFISWARM_BRIDGE_URL="$BRIDGE" \
    nohup "$BIN_DIR/cofiswarm-rag-worker" -listen :8018 >>"$LOGDIR/rag-worker-8018.log" 2>&1 &
  echo "started: rag-worker :8018 pid $!"
fi

echo "host-rag launch dispatched (logs in $LOGDIR)"
