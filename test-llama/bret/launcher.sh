cd /caribou/test-llama

cat > start-server.sh << 'EOF'
#!/bin/bash
# start-server.sh - Launcher for llama-server

# Paths
BINARY_PATH="/Users/Shared/llama/llama-server"
MODEL_DIR="/caribou/test-llama/models"

# ====================== CONFIG ======================
MODEL_NAME="your-model.gguf"                     # ← Change this
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"

CTX_SIZE=8192
PARALLEL_SLOTS=4
GPU_LAYERS=99
PORT=8080
CPU_THREADS=8

echo "=== llama.cpp Server Launcher ==="
echo "Binary     : $BINARY_PATH"
echo "Model      : $MODEL_PATH"
echo "Working Dir: $(pwd)"
echo "Parallel   : $PARALLEL_SLOTS slots"
echo "Port       : $PORT"
echo "================================="

# Check binary exists
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Error: llama-server not found at $BINARY_PATH"
    echo "Make sure it exists in /Users/Shared/llama/"
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

# Start the server
"$BINARY_PATH" \
  -m "$MODEL_PATH" \
  -c $CTX_SIZE \
  --n-gpu-layers $GPU_LAYERS \
  --parallel $PARALLEL_SLOTS \
  --cont-batching \
  -fa \
  --port $PORT \
  -t $CPU_THREADS \
  --no-mmap \
  --log-disable
EOF
