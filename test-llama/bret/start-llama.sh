#!/bin/bash

BINARY="/Users/Shared/llama/llama-server.new"
MODEL="/Users/caribou/test-llama/models/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"
PORT=8080

mkdir -p "$(dirname "$MODEL")"
if [ ! -f "$MODEL" ]; then
    cp "/Users/Shared/llama/models/medium/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf" "$MODEL"
fi

echo "🚀 Starting llama.cpp server on port $PORT"
echo "Press Ctrl+C to stop"

"$BINARY" \
  -m "$MODEL" \
  -c 8192 \
  --n-gpu-layers 99 \
  --parallel 4 \
  --cont-batching \
  -fa \
  --port $PORT \
  -t 8 \
  --no-mmap \
  --log-disable
