#!/bin/bash
#
# start-llama.sh — launch the llama.cpp server for the chat backend.
#
# All settings are overridable via environment variables, e.g.:
#   MODEL=/path/to/other.gguf PORT=9000 ./start-llama.sh
#   MODEL_DIR=~/models MODEL_FILE=Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf ./start-llama.sh
#
# Defaults target the high-throughput Llama-3.2-1B Q4_K_M build (~250 tok/s
# decode on M3 Max). For higher quality at ~50 tok/s, point MODEL_FILE at the
# 8B model: MODEL_FILE=Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf

BINARY="${LLAMA_BINARY:-/Users/Shared/llama/llama-server.new}"
MODEL_DIR="${MODEL_DIR:-/Users/caribou/test-llama/models}"
MODEL_FILE="${MODEL_FILE:-Llama-3.2-1B-Instruct-Q4_K_M.gguf}"
MODEL="${MODEL:-$MODEL_DIR/$MODEL_FILE}"

PORT="${PORT:-8080}"
CTX_SIZE="${CTX_SIZE:-8192}"
GPU_LAYERS="${GPU_LAYERS:-99}"
PARALLEL_SLOTS="${PARALLEL_SLOTS:-4}"
CPU_THREADS="${CPU_THREADS:-8}"

# Fail loudly if the binary or model is missing instead of starting a broken server.
if [ ! -x "$BINARY" ]; then
    echo "❌ Error: llama-server binary not found or not executable at $BINARY" >&2
    echo "   Set LLAMA_BINARY=/path/to/llama-server to override." >&2
    exit 1
fi

if [ ! -f "$MODEL" ]; then
    echo "❌ Error: model not found at $MODEL" >&2
    echo "   Available models in $MODEL_DIR:" >&2
    ls -lh "$MODEL_DIR"/*.gguf 2>/dev/null >&2 || echo "   (none)" >&2
    echo "   Override with MODEL=/path/to/model.gguf or MODEL_FILE=name.gguf" >&2
    exit 1
fi

echo "🚀 Starting llama.cpp server on port $PORT"
echo "   Model: $(basename "$MODEL")  |  ctx: $CTX_SIZE  |  gpu-layers: $GPU_LAYERS"
echo "Press Ctrl+C to stop"

"$BINARY" \
  -m "$MODEL" \
  -c "$CTX_SIZE" \
  --n-gpu-layers "$GPU_LAYERS" \
  --parallel "$PARALLEL_SLOTS" \
  --cont-batching \
  -fa \
  --port "$PORT" \
  -t "$CPU_THREADS" \
  --no-mmap \
  --log-disable
