#!/bin/bash
# quantize.sh - Quantize a high-precision GGUF using an importance matrix
# Pipeline: imatrix.sh -> quantize.sh -> start-perplexity.sh / start-bench.sh

# Paths
BINARY_PATH="/Users/Shared/llama/llama.cpp/build/bin/llama-quantize"
MODEL_DIR="/Users/caribou/test-llama/models"

# ====================== CONFIG ======================
# Source should be the SAME high-precision GGUF used for imatrix.sh.
SRC_NAME="Meta-Llama-3.1-8B-Instruct-Q8_0.gguf"
SOURCE_MODEL="${1:-$MODEL_DIR/$SRC_NAME}"

QUANT_TYPE="${2:-Q4_K_M}"   # target type: Q4_K_M, Q5_K_M, Q6_K, Q8_0, ...

IMATRIX="$MODEL_DIR/$(basename "${SOURCE_MODEL%.gguf}").imatrix.gguf"
OUTPUT_MODEL="$MODEL_DIR/$(basename "${SOURCE_MODEL%.gguf}")-${QUANT_TYPE}-imat.gguf"

echo "=== llama.cpp Quantize ==="
echo "Binary     : $BINARY_PATH"
echo "Source     : $SOURCE_MODEL"
echo "Imatrix    : $IMATRIX"
echo "Target     : $QUANT_TYPE"
echo "Output     : $OUTPUT_MODEL"
echo "=========================="

# Check binary exists
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Error: llama-quantize not found at $BINARY_PATH"
    echo "Make sure it is built in /Users/Shared/llama/llama.cpp/build/bin/"
    exit 1
fi

# Check source model exists
if [ ! -f "$SOURCE_MODEL" ]; then
    echo "❌ Error: Source model not found at $SOURCE_MODEL"
    echo "Provide a high-precision (F16/Q8_0) GGUF as the first argument."
    exit 1
fi

# Build the quantize command; include imatrix only if it exists.
# --allow-requantize is needed when the source is already quantized (e.g. Q8_0).
IMATRIX_ARGS=(--allow-requantize)
if [ -f "$IMATRIX" ]; then
    IMATRIX_ARGS+=(--imatrix "$IMATRIX")
else
    echo "⚠️  Warning: imatrix not found at $IMATRIX"
    echo "   Proceeding WITHOUT it (lower quality). Run ./imatrix.sh first for best results."
fi

# Quantize
"$BINARY_PATH" \
  "${IMATRIX_ARGS[@]}" \
  "$SOURCE_MODEL" \
  "$OUTPUT_MODEL" \
  "$QUANT_TYPE"

if [ $? -ne 0 ] || [ ! -f "$OUTPUT_MODEL" ]; then
    echo "❌ Error: quantization failed; no output written"
    exit 1
fi

echo "✅ Quantized model written to $OUTPUT_MODEL"
echo "   Evaluate it:"
echo "     ./start-perplexity.sh   (edit MODEL_NAME to $(basename "$OUTPUT_MODEL"))"
echo "     ./start-bench.sh        (edit MODEL_NAME to $(basename "$OUTPUT_MODEL"))"
