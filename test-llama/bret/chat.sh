#!/bin/bash
# chat.sh - Launcher for llama-cli (local interactive / one-shot inference)
#   ./chat.sh                       → interactive chat
#   ./chat.sh "your prompt here"    → one-shot answer, then exit

# Paths
BINARY_PATH="/Users/Shared/llama/llama.cpp/build/bin/llama-cli"
MODEL_DIR="/Users/caribou/test-llama/models"

# ====================== CONFIG ======================
MODEL_NAME="Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"   # ← Change this
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"

SYSTEM_PROMPT="You are a helpful, concise assistant."
CTX_SIZE=8192
GPU_LAYERS=99
CPU_THREADS=8
N_PREDICT=512       # max tokens to generate (-1 = unlimited)

PROMPT="$1"         # optional: pass a prompt as $1 for one-shot mode

echo "=== llama.cpp Chat Launcher ==="
echo "Binary     : $BINARY_PATH"
echo "Model      : $MODEL_PATH"
if [ -n "$PROMPT" ]; then
    echo "Mode       : one-shot (single turn)"
else
    echo "Mode       : interactive (Ctrl+C to exit)"
fi
echo "==============================="

# Check binary exists
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Error: llama-cli not found at $BINARY_PATH"
    echo "Make sure it is built in /Users/Shared/llama/llama.cpp/build/bin/"
    exit 1
fi

# Check model exists
if [ ! -f "$MODEL_PATH" ]; then
    echo "❌ Error: Model not found at $MODEL_PATH"
    echo "Available models:"
    ls -lh "$MODEL_DIR/" 2>/dev/null || echo "   (models folder empty)"
    exit 1
fi

# Common args
ARGS=(
  -m "$MODEL_PATH"
  -sys "$SYSTEM_PROMPT"
  -c $CTX_SIZE
  --n-gpu-layers $GPU_LAYERS
  -t $CPU_THREADS
  -n $N_PREDICT
  -co on
)

# One-shot if a prompt was given, otherwise interactive conversation
if [ -n "$PROMPT" ]; then
    "$BINARY_PATH" "${ARGS[@]}" -st -p "$PROMPT"
else
    "$BINARY_PATH" "${ARGS[@]}" -cnv
fi
