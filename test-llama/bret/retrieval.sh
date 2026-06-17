#!/bin/bash
# retrieval.sh - Launcher for llama-retrieval (semantic search / mini-RAG)
#   ./retrieval.sh <context-file> ["query text"]
# Chunks the context file, embeds it, and ranks chunks by similarity to a query.

# Paths
BINARY_PATH="/Users/Shared/llama/llama.cpp/build/bin/llama-retrieval"
MODEL_DIR="/Users/caribou/test-llama/models"

# ====================== CONFIG ======================
# NOTE: a dedicated embedding model (nomic-embed, bge) ranks far better than a
# causal chat model. Override MODEL_NAME for serious retrieval work.
MODEL_NAME="Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"   # ← Change this
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"

CONTEXT_FILE="$1"                       # required: text file to search
QUERY="$2"                              # optional: query (interactive if omitted)

CTX_SIZE=512
GPU_LAYERS=99
CPU_THREADS=8
TOP_K=3                                 # number of chunks to return
CHUNK_SIZE=128                          # min chars per embedded chunk
CHUNK_SEP="."                           # split chunks on this separator
POOLING=mean                            # required: causal models default to NONE (unsupported here)

echo "=== llama.cpp Retrieval Launcher ===" 1>&2
echo "Binary     : $BINARY_PATH" 1>&2
echo "Model      : $MODEL_PATH" 1>&2
echo "Context    : $CONTEXT_FILE" 1>&2
echo "Top-K      : $TOP_K | Chunk size: $CHUNK_SIZE" 1>&2
echo "====================================" 1>&2

# Check binary exists
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Error: llama-retrieval not found at $BINARY_PATH" 1>&2
    echo "Make sure it is built in /Users/Shared/llama/llama.cpp/build/bin/" 1>&2
    exit 1
fi

# Check model exists
if [ ! -f "$MODEL_PATH" ]; then
    echo "❌ Error: Model not found at $MODEL_PATH" 1>&2
    ls -lh "$MODEL_DIR/" 2>/dev/null 1>&2 || echo "   (models folder empty)" 1>&2
    exit 1
fi

# Check context file
if [ -z "$CONTEXT_FILE" ]; then
    echo "❌ Error: no context file given" 1>&2
    echo "Usage: ./retrieval.sh <context-file> [\"query text\"]" 1>&2
    exit 1
fi
if [ ! -f "$CONTEXT_FILE" ]; then
    echo "❌ Error: context file not found at $CONTEXT_FILE" 1>&2
    exit 1
fi

# Build args; feed the query via stdin when provided (one-shot), else interactive
ARGS=(
  -m "$MODEL_PATH"
  --context-file "$CONTEXT_FILE"
  --chunk-size $CHUNK_SIZE
  --chunk-separator "$CHUNK_SEP"
  --pooling "$POOLING"
  --top-k $TOP_K
  -c $CTX_SIZE
  --n-gpu-layers $GPU_LAYERS
  -t $CPU_THREADS
)

if [ -n "$QUERY" ]; then
    printf '%s\n' "$QUERY" | "$BINARY_PATH" "${ARGS[@]}"
else
    "$BINARY_PATH" "${ARGS[@]}"
fi
