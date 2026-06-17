# 1. Go to the correct directory
cd /Users/Shared/llama

# 2. Create a clean parallel.sh script here (since your binary is here)
cat > parallel.sh << 'EOF'
#!/bin/bash
# parallel.sh - llama.cpp server for M3

# ====================== EDIT THIS ======================
MODEL_PATH="/Users/Shared/llama/models/medium/Meta-Llama-3.1-8B-Instruct-Q4_K_M.ggufyour-model.gguf"   # ← CHANGE TO YOUR ACTUAL MODEL

CTX_SIZE=8192
PARALLEL_SLOTS=4
GPU_LAYERS=99
PORT=8080
CPU_THREADS=8

echo "=== Starting llama.cpp server ==="
echo "Model      : $MODEL_PATH"
echo "Parallel   : $PARALLEL_SLOTS slots"
echo "Context    : $CTX_SIZE"
echo "GPU Layers : $GPU_LAYERS"
echo "Port       : $PORT"
echo "================================="

./llama-server \
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
