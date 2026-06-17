#!/bin/bash
# imatrix.sh - Generate an importance matrix for higher-quality quantization
# Pipeline: imatrix.sh -> quantize.sh -> start-perplexity.sh / start-bench.sh

# Paths
BINARY_PATH="/Users/Shared/llama/llama.cpp/build/bin/llama-imatrix"
MODEL_DIR="/Users/caribou/test-llama/models"

# ====================== CONFIG ======================
# Source should be a HIGH-PRECISION GGUF (F16 or Q8_0). Re-quantizing an
# already-Q4 model only degrades quality. Pass a path as $1 to override.
SRC_NAME="Meta-Llama-3.1-8B-Instruct-Q8_0.gguf"
SOURCE_MODEL="${1:-$MODEL_DIR/$SRC_NAME}"

# Calibration text (reuses the wikitext-2 data fetched by start-perplexity.sh)
DATASET="${2:-$MODEL_DIR/wikitext-2-raw/wiki.train.raw}"

OUTPUT_IMATRIX="$MODEL_DIR/$(basename "${SOURCE_MODEL%.gguf}").imatrix.gguf"
CTX_SIZE=512
GPU_LAYERS=99
CHUNKS=200          # number of calibration chunks (-1 = all; 200 is plenty)

echo "=== llama.cpp Importance Matrix ==="
echo "Binary     : $BINARY_PATH"
echo "Source     : $SOURCE_MODEL"
echo "Calibration: $DATASET"
echo "Output     : $OUTPUT_IMATRIX"
echo "Chunks     : $CHUNKS"
echo "==================================="

# Check binary exists
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Error: llama-imatrix not found at $BINARY_PATH"
    echo "Make sure it is built in /Users/Shared/llama/llama.cpp/build/bin/"
    exit 1
fi

# Check source model exists
if [ ! -f "$SOURCE_MODEL" ]; then
    echo "❌ Error: Source model not found at $SOURCE_MODEL"
    echo "imatrix needs a high-precision (F16/Q8_0) GGUF. To get one:"
    echo "  • Download an F16 GGUF, e.g.:"
    echo "      llama-cli -hf <user>/<repo>:F16   (downloads to HF cache)"
    echo "  • Or convert from HF safetensors:"
    echo "      python convert_hf_to_gguf.py <model_dir> --outtype f16"
    exit 1
fi

# Check calibration dataset exists
if [ ! -f "$DATASET" ]; then
    echo "❌ Error: Calibration text not found at $DATASET"
    echo "Run ./start-perplexity.sh once to auto-download wikitext-2,"
    echo "or pass a text file as the second argument."
    exit 1
fi

# Generate the importance matrix
"$BINARY_PATH" \
  -m "$SOURCE_MODEL" \
  -f "$DATASET" \
  -o "$OUTPUT_IMATRIX" \
  -c $CTX_SIZE \
  --n-gpu-layers $GPU_LAYERS \
  --chunks $CHUNKS

if [ $? -ne 0 ] || [ ! -f "$OUTPUT_IMATRIX" ]; then
    echo "❌ Error: imatrix generation failed; no output written"
    exit 1
fi

echo "✅ Importance matrix written to $OUTPUT_IMATRIX"
echo "   Next: ./quantize.sh \"$SOURCE_MODEL\""
