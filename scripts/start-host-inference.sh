#!/usr/bin/env bash
# Launch the host llama.cpp + MLX inference servers the Dockerized cofiswarm stack fronts
# (Metal, outside compose). Idempotent: skips a server already answering /v1/models, so it is
# safe to re-run and safe as a LaunchAgent (com.cofiswarm.host-inference, RunAtLoad) for reboot
# survival. Port->model map mirrors cofiswarm-slot-manager/configs/endpoints.json.
set -uo pipefail

LLAMA_BIN="${COFISWARM_LLAMA_SERVER:-/Users/Shared/llama/llama.cpp-master/build/bin/llama-server}"
MODELS="${COFISWARM_LLAMA_MODELS:-/Users/Shared/llama/models}"
MLX_PY="${COFISWARM_MLX_PYTHON:-$HOME/.venv-mlx/bin/python}"
MLX_MODEL="${COFISWARM_MLX_MODEL:-$MODELS/MLX/MLX/Llama-3.2-1B-Instruct-4bit}"
LOGDIR="${COFISWARM_INFER_LOGDIR:-$HOME/Library/Logs/cofiswarm}"
CTX="${COFISWARM_LLAMA_CTX:-4096}"
mkdir -p "$LOGDIR"

# A loading server binds its port well before /v1/models answers, so guard launches on the
# port being LISTEN-bound (reliable) rather than HTTP readiness (flaky under load) — otherwise a
# slow-starting server gets a duplicate spawned that then fails to bind.
bound() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

start_llama() { # port model agents...
  local port="$1" model="$2"
  if bound "$port"; then echo "ok: llama :$port already bound"; return 0; fi
  if [[ ! -f "$model" ]]; then echo "FAIL: missing model $model" >&2; return 1; fi
  if [[ ! -x "$LLAMA_BIN" ]]; then echo "FAIL: llama-server not at $LLAMA_BIN" >&2; return 1; fi
  nohup "$LLAMA_BIN" -m "$model" --host 127.0.0.1 --port "$port" -c "$CTX" -ngl 99 \
    >>"$LOGDIR/llama-$port.log" 2>&1 &
  echo "started: llama :$port ($(basename "$model")) pid $!"
}

# --- llama.cpp servers (Metal) -------------------------------------------------------------
start_llama 8086 "$MODELS/medium/qwen2.5-coder-7b-instruct-q4_k_m.gguf"   # coder7b
start_llama 8085 "$MODELS/medium/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"  # llama8b
start_llama 8084 "$MODELS/large/gemma-2-9b-it-Q4_K_M.gguf"                # gemma9b
start_llama 8087 "$MODELS/small/gemma-2-2b-it-Q4_K_M.gguf"                # gemma2b

# --- MLX server (mlx-scout) ----------------------------------------------------------------
# Some MLX conversions ship a bogus tokenizer_class ("TokenizersBackend") that transformers
# rejects on load; normalize it to PreTrainedTokenizerFast (idempotent, backup kept) so a fresh
# model pull can't silently break mlx-scout. The model carries a real tokenizer.json.
patch_mlx_tokenizer() {
  local tc="$MLX_MODEL/tokenizer_config.json"
  [[ -f "$tc" ]] || return 0
  grep -q '"TokenizersBackend"' "$tc" || return 0
  cp -n "$tc" "$tc.bak" 2>/dev/null || true
  /usr/bin/python3 - "$tc" <<'PY' && echo "patched: MLX tokenizer_class -> PreTrainedTokenizerFast"
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["tokenizer_class"] = "PreTrainedTokenizerFast"
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
PY
}

if bound 8083; then
  echo "ok: mlx :8083 already bound"
elif [[ ! -x "$MLX_PY" ]]; then
  echo "FAIL: MLX python not at $MLX_PY" >&2
elif [[ ! -d "$MLX_MODEL" ]]; then
  echo "FAIL: missing MLX model dir $MLX_MODEL" >&2
else
  patch_mlx_tokenizer
  nohup "$MLX_PY" -m mlx_lm server --model "$MLX_MODEL" --port 8083 --host 127.0.0.1 \
    >>"$LOGDIR/mlx-8083.log" 2>&1 &
  echo "started: mlx :8083 ($(basename "$MLX_MODEL")) pid $!"
fi

echo "host-inference launch dispatched (logs in $LOGDIR)"
