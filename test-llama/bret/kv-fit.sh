#!/bin/bash
# kv-fit.sh - KV-cache memory planner. Will a given ctx x parallel fit in RAM?
#
# Computes the KV-cache footprint for the model geometry + KV-quant types below,
# compares it against a memory budget (default 70% of system RAM minus the model
# file), and prints a fit verdict plus a sweep of context sizes. Catches OOM
# BEFORE you launch instead of after.
#
# KV bytes = n_layer * total_tokens * n_kv_head * head_dim * (bitsK + bitsV)/8
#   where total_tokens = CTX * PARALLEL  (worst case: every slot full).
#
# Usage:
#   ./kv-fit.sh                 # report for the configured CTX x PARALLEL + sweep
#   ./kv-fit.sh 16384 4         # override: ctx=16384, parallel=4

set -euo pipefail

# ====================== PATHS ======================
MODEL_DIR="/Users/caribou/test-llama/models"
MODEL_NAME="Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"

# ====================== CONFIG ======================
# Model KV geometry (Llama-3.1-8B defaults — adjust per model).
N_LAYER=32
N_KV_HEAD=8
HEAD_DIM=128

KV_TYPE_K="q8_0"            # must match start-kvquant.sh -ctk
KV_TYPE_V="q8_0"            # must match start-kvquant.sh -ctv
CTX="${1:-8192}"           # context size (per slot)
PARALLEL="${2:-4}"         # --parallel slots
BUDGET_FRACTION="${BUDGET_FRACTION:-0.70}"   # fraction of RAM usable
SWEEP_CTX=(2048 4096 8192 16384 32768)

# Approximate bits-per-element per ggml type (includes block scale overhead).
bits_for() {
    case "$1" in
        f32) echo 32 ;; f16|bf16) echo 16 ;; q8_0) echo 8.5 ;;
        q5_1) echo 6 ;; q5_0) echo 5.5 ;; q4_1) echo 5 ;;
        q4_0|iq4_nl) echo 4.5 ;;
        *) echo "" ;;
    esac
}

BITS_K="$(bits_for "$KV_TYPE_K")"
BITS_V="$(bits_for "$KV_TYPE_V")"
if [ -z "$BITS_K" ] || [ -z "$BITS_V" ]; then
    echo "❌ Error: unknown KV type (K=$KV_TYPE_K V=$KV_TYPE_V)." >&2
    echo "   Valid: f32 f16 bf16 q8_0 q5_1 q5_0 q4_1 q4_0 iq4_nl" >&2
    exit 1
fi

# Total system RAM in bytes (macOS: sysctl; Linux: /proc/meminfo).
if RAM_BYTES="$(sysctl -n hw.memsize 2>/dev/null)" && [ -n "$RAM_BYTES" ]; then
    :
elif [ -r /proc/meminfo ]; then
    RAM_BYTES=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) * 1024 ))
else
    echo "❌ Error: could not determine system RAM." >&2
    exit 1
fi

# Model file size (consumed memory baseline); 0 if missing (warn, don't fail).
if [ -f "$MODEL_PATH" ]; then
    MODEL_BYTES=$(stat -f%z "$MODEL_PATH" 2>/dev/null || stat -c%s "$MODEL_PATH" 2>/dev/null || echo 0)
else
    echo "⚠️  Model not found at $MODEL_PATH — model footprint excluded from budget." >&2
    MODEL_BYTES=0
fi

# KV bytes for a given ctx + parallel.
kv_bytes() {
    awk -v L="$N_LAYER" -v h="$N_KV_HEAD" -v d="$HEAD_DIM" -v bk="$BITS_K" -v bv="$BITS_V" \
        -v c="$1" -v p="$2" 'BEGIN { printf "%.0f", L*(c*p)*h*d*(bk+bv)/8 }'
}
gib() { awk -v b="$1" 'BEGIN { printf "%.2f", b/(1024*1024*1024) }'; }

BUDGET_BYTES=$(awk -v r="$RAM_BYTES" -v f="$BUDGET_FRACTION" 'BEGIN { printf "%.0f", r*f }')
AVAIL_FOR_KV=$(( BUDGET_BYTES - MODEL_BYTES ))

echo "=== KV-cache fit planner ==="
echo "Model     : $MODEL_NAME ($(gib "$MODEL_BYTES") GiB on disk)"
echo "Geometry  : layers=$N_LAYER kv_heads=$N_KV_HEAD head_dim=$HEAD_DIM"
echo "KV types  : K=$KV_TYPE_K ($BITS_K bit) V=$KV_TYPE_V ($BITS_V bit)"
echo "System RAM: $(gib "$RAM_BYTES") GiB  •  budget ${BUDGET_FRACTION} = $(gib "$BUDGET_BYTES") GiB"
echo "KV budget : $(gib "$AVAIL_FOR_KV") GiB (budget minus model)"
echo "============================"

# --- Verdict for the requested config ---
NEED=$(kv_bytes "$CTX" "$PARALLEL")
echo
echo "Requested : ctx=$CTX x parallel=$PARALLEL  ->  KV = $(gib "$NEED") GiB"
if [ "$NEED" -le "$AVAIL_FOR_KV" ]; then
    echo "Verdict   : ✅ FITS (headroom $(gib $(( AVAIL_FOR_KV - NEED ))) GiB)"
else
    echo "Verdict   : ❌ DOES NOT FIT (over by $(gib $(( NEED - AVAIL_FOR_KV ))) GiB)"
fi

# --- Largest ctx that fits at this parallel ---
PER_SLOT_TOK_BYTES=$(awk -v L="$N_LAYER" -v h="$N_KV_HEAD" -v d="$HEAD_DIM" -v bk="$BITS_K" -v bv="$BITS_V" \
    -v p="$PARALLEL" 'BEGIN { printf "%.6f", L*p*h*d*(bk+bv)/8 }')
MAX_CTX=$(awk -v a="$AVAIL_FOR_KV" -v t="$PER_SLOT_TOK_BYTES" 'BEGIN { printf "%d", (t>0)? a/t : 0 }')
echo
echo "Max ctx at parallel=$PARALLEL: ~$MAX_CTX tokens/slot fits the KV budget."

# --- Sweep table ---
echo
echo "| ctx/slot | parallel | KV (GiB) | fits? |"
echo "|---------:|---------:|---------:|:-----:|"
for c in "${SWEEP_CTX[@]}"; do
    b=$(kv_bytes "$c" "$PARALLEL")
    if [ "$b" -le "$AVAIL_FOR_KV" ]; then fit="✅"; else fit="❌"; fi
    printf "| %8s | %8s | %8s | %s |\n" "$c" "$PARALLEL" "$(gib "$b")" "$fit"
done

echo
echo "Note: assumes every slot fills to ctx (worst case). With --kv-unified the live"
echo "      footprint can be lower if slots share a smaller total context."
