#!/bin/bash
# embed.sh - Launcher for llama-embedding (text -> embedding vectors)
#   ./embed.sh "some text"                        → embed one string
#   ./embed.sh "text A" "text B"                  → embed multiple strings
#   echo -e "line1\nline2" | ./embed.sh           → embed each stdin line

# Paths
BINARY_PATH="/Users/Shared/llama/llama.cpp/build/bin/llama-embedding"
MODEL_DIR="/Users/caribou/test-llama/models"

# ====================== CONFIG ======================
# NOTE: a dedicated embedding model (e.g. nomic-embed, bge) gives far better
# vectors than a causal chat model. Override MODEL_NAME for real retrieval work.
MODEL_NAME="Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"   # ← Change this
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"

CTX_SIZE=512
GPU_LAYERS=99
CPU_THREADS=8
POOLING=mean              # none | mean | cls | last | rank
OUTPUT_FORMAT=json        # empty | array | json | json+
SEPARATOR="<#sep#>"       # separates multiple inputs

echo "=== llama.cpp Embedding Launcher ===" 1>&2
echo "Binary     : $BINARY_PATH" 1>&2
echo "Model      : $MODEL_PATH" 1>&2
echo "Pooling    : $POOLING | Format: $OUTPUT_FORMAT" 1>&2
echo "====================================" 1>&2

# Check binary exists
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Error: llama-embedding not found at $BINARY_PATH" 1>&2
    echo "Make sure it is built in /Users/Shared/llama/llama.cpp/build/bin/" 1>&2
    exit 1
fi

# Check model exists
if [ ! -f "$MODEL_PATH" ]; then
    echo "❌ Error: Model not found at $MODEL_PATH" 1>&2
    echo "Available models:" 1>&2
    ls -lh "$MODEL_DIR/" 2>/dev/null 1>&2 || echo "   (models folder empty)" 1>&2
    exit 1
fi

# Collect input: args take priority, otherwise read stdin lines
if [ "$#" -gt 0 ]; then
    INPUT=$(printf '%s\n' "$@")
else
    INPUT=$(cat)
fi

if [ -z "$INPUT" ]; then
    echo "❌ Error: no input text provided" 1>&2
    echo "Pass text as arguments or pipe it via stdin." 1>&2
    exit 1
fi

# Join lines with the separator so each input becomes its own embedding
JOINED=$(printf '%s' "$INPUT" | paste -sd '~' - | sed "s/~/$SEPARATOR/g")

# Generate embeddings
"$BINARY_PATH" \
  -m "$MODEL_PATH" \
  -p "$JOINED" \
  --embd-separator "$SEPARATOR" \
  --embd-output-format "$OUTPUT_FORMAT" \
  --pooling "$POOLING" \
  -c $CTX_SIZE \
  --n-gpu-layers $GPU_LAYERS \
  -t $CPU_THREADS
