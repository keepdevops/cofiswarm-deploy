#!/bin/bash
# start-perplexity.sh - Launcher for llama-perplexity (model quality eval)

# Paths
BINARY_PATH="/Users/Shared/llama/llama.cpp/build/bin/llama-perplexity"
MODEL_DIR="/Users/caribou/test-llama/models"

# ====================== CONFIG ======================
MODEL_NAME="Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"   # ← Change this
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"

DATASET="${1:-$MODEL_DIR/wikitext-2-raw/wiki.test.raw}"  # ← Pass a file as $1 to override
CTX_SIZE=512
GPU_LAYERS=99
CPU_THREADS=8

echo "=== llama.cpp Perplexity Launcher ==="
echo "Binary     : $BINARY_PATH"
echo "Model      : $MODEL_PATH"
echo "Dataset    : $DATASET"
echo "Context    : $CTX_SIZE"
echo "====================================="

# Check binary exists
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Error: llama-perplexity not found at $BINARY_PATH"
    echo "Make sure it is built in /Users/Shared/llama/llama.cpp/build/bin/"
    exit 1
fi

# Check model exists
if [ ! -f "$MODEL_PATH" ]; then
    echo "❌ Error: Model not found at $MODEL_PATH"
    echo "Available models:"
    ls -lh "$MODEL_DIR/" 2>/dev/null || echo "   (models folder empty)"
    echo "Please copy your .gguf model into $MODEL_DIR/"
    exit 1
fi

# Default dataset: auto-download wikitext-2 if missing
WIKITEXT_URL="https://huggingface.co/datasets/ggml-org/ci/resolve/main/wikitext-2-raw-v1.zip"
WIKITEXT_DIR="$MODEL_DIR/wikitext-2-raw"
DEFAULT_DATASET="$WIKITEXT_DIR/wiki.test.raw"

if [ ! -f "$DATASET" ] && [ "$DATASET" = "$DEFAULT_DATASET" ]; then
    echo "ℹ️  Dataset not found, downloading wikitext-2-raw..."
    ZIP_PATH="$MODEL_DIR/wikitext-2-raw-v1.zip"
    if ! curl -L -f -o "$ZIP_PATH" "$WIKITEXT_URL"; then
        echo "❌ Error: Failed to download wikitext-2 from $WIKITEXT_URL"
        exit 1
    fi
    if ! unzip -o "$ZIP_PATH" -d "$MODEL_DIR"; then
        echo "❌ Error: Failed to unzip $ZIP_PATH"
        exit 1
    fi
    rm -f "$ZIP_PATH"
    echo "✅ wikitext-2-raw ready at $WIKITEXT_DIR"
fi

# Check dataset exists
if [ ! -f "$DATASET" ]; then
    echo "❌ Error: Dataset not found at $DATASET"
    echo "Provide a raw text file as the first argument, e.g.:"
    echo "   ./start-perplexity.sh /path/to/wiki.test.raw"
    exit 1
fi

# Run the perplexity eval
"$BINARY_PATH" \
  -m "$MODEL_PATH" \
  -f "$DATASET" \
  -c $CTX_SIZE \
  --n-gpu-layers $GPU_LAYERS \
  -t $CPU_THREADS
