#!/bin/bash
# ppl-tpquant.sh - Compare KV-quant profiles by perplexity on wikitext-2.
#
# Runs llama-perplexity once per profile with that profile's real llama.cpp KV
# types (see start-tpquant.sh for the profile->type mapping rationale) and prints
# the final PPL for each plus the delta vs the q8_0 near-lossless baseline.
#
# Quantized KV requires flash-attn (-fa on); we force it for every profile here.
#
# Usage:
#   ./ppl-tpquant.sh                      # compares: polarquant q8_0
#   ./ppl-tpquant.sh turboquant q8_0 f16  # custom profile list
#   CHUNKS=50 ./ppl-tpquant.sh            # cap chunks for a faster run

set -euo pipefail

# ====================== PATHS ======================
BINARY_PATH="/Users/Shared/llama/llama.cpp/build/bin/llama-perplexity"
MODEL_DIR="/Users/caribou/test-llama/models"
MODEL_NAME="Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"
DATASET="$MODEL_DIR/wikitext-2-raw/wiki.test.raw"

# ====================== CONFIG ======================
CTX_SIZE=512
GPU_LAYERS=99
CPU_THREADS=8
CHUNKS="${CHUNKS:-0}"            # 0 = full dataset; >0 caps with --chunks
PROFILES=("${@:-polarquant q8_0}")
# Re-split in case profiles came through as a single default string.
read -r -a PROFILES <<< "${PROFILES[*]}"

# Same profile->KV-type mapping as start-tpquant.sh.
kv_for_profile() {
  case "$1" in
    turboquant) echo "q5_1 q5_1" ;;
    polarquant) echo "q8_0 q4_0" ;;
    q8_0)       echo "q8_0 q8_0" ;;
    f16)        echo "f16 f16" ;;
    *) echo "❌ Error: unknown profile '$1' (turboquant|polarquant|q8_0|f16)" >&2; return 1 ;;
  esac
}

# ====================== GUARDS (fail loudly) ======================
for f in "$BINARY_PATH" "$MODEL_PATH" "$DATASET"; do
  if [ ! -f "$f" ]; then
    echo "❌ Error: required file not found: $f" >&2
    exit 1
  fi
done

echo "=== KV-quant perplexity comparison ==="
echo "Model    : $MODEL_NAME"
echo "Dataset  : wikitext-2 (ctx=$CTX_SIZE, chunks=$([ "$CHUNKS" = 0 ] && echo full || echo "$CHUNKS"))"
echo "Profiles : ${PROFILES[*]}"
echo "======================================"

LOG_DIR="$(mktemp -d)"
declare -a NAMES PPLS

for prof in "${PROFILES[@]}"; do
  read -r ctk ctv <<< "$(kv_for_profile "$prof")"
  echo ""
  echo ">>> Profile '$prof' : K=$ctk V=$ctv  (running...)"

  ARGS=(
    -m "$MODEL_PATH"
    -f "$DATASET"
    -c "$CTX_SIZE"
    --n-gpu-layers "$GPU_LAYERS"
    -t "$CPU_THREADS"
    -fa on
    -ctk "$ctk"
    -ctv "$ctv"
  )
  [ "$CHUNKS" != "0" ] && ARGS+=( --chunks "$CHUNKS" )

  LOG="$LOG_DIR/$prof.log"
  # Fail loudly if the eval itself errors out.
  if ! "$BINARY_PATH" "${ARGS[@]}" 2>&1 | tee "$LOG"; then
    echo "❌ Error: perplexity run failed for profile '$prof' (see $LOG)" >&2
    exit 1
  fi

  # Parse "Final estimate: PPL = <n> +/- <m>" (fall back to last "PPL =").
  ppl="$(grep -Eo 'PPL = [0-9]+\.[0-9]+' "$LOG" | tail -1 | awk '{print $3}')"
  if [ -z "$ppl" ]; then
    echo "❌ Error: could not parse PPL from $LOG" >&2
    exit 1
  fi
  NAMES+=("$prof:$ctk/$ctv"); PPLS+=("$ppl")
done

# ====================== SUMMARY ======================
echo ""
echo "================ RESULTS ================"
printf "%-22s %12s %14s\n" "profile (K/V)" "PPL" "Δ vs q8_0 %"

# Find q8_0 baseline PPL for delta, if present in this run.
base=""
for i in "${!PROFILES[@]}"; do
  [ "${PROFILES[$i]}" = "q8_0" ] && base="${PPLS[$i]}"
done

for i in "${!NAMES[@]}"; do
  if [ -n "$base" ]; then
    delta="$(awk -v p="${PPLS[$i]}" -v b="$base" 'BEGIN{printf "%+.3f", (p-b)/b*100}')"
  else
    delta="n/a"
  fi
  printf "%-22s %12s %14s\n" "${NAMES[$i]}" "${PPLS[$i]}" "$delta"
done
echo "========================================"
echo "(lower PPL = better; q8_0 is the near-lossless reference)"

rm -rf "$LOG_DIR"
