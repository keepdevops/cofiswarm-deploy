#!/bin/bash
# kv-sweep.sh - sweep KV-cache quantization types and report speed + quality + memory.
#
# Answers "is q8_0 actually the right -ctk/-ctv default?" by running, for each KV
# type: llama-bench (prefill + generation throughput) and optionally
# llama-perplexity (quality), plus an analytic KV-memory estimate. Results land in
# one markdown table (stdout + kv-sweep-results.md).
#
# Flash Attention is forced on (-fa 1): quantized KV cache requires it.
#
# Usage:
#   ./kv-sweep.sh                 # speed + memory sweep (fast)
#   RUN_PPL=1 ./kv-sweep.sh       # also run perplexity per type (slow)

set -euo pipefail

# ====================== PATHS ======================
BENCH_BIN="/Users/Shared/llama/llama.cpp/build/bin/llama-bench"
PPL_BIN="/Users/Shared/llama/llama.cpp/build/bin/llama-perplexity"
MODEL_DIR="/Users/caribou/test-llama/models"
MODEL_NAME="Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"

# ====================== CONFIG ======================
KV_TYPES=(f16 q8_0 q4_0)   # KV types to sweep (applied to both -ctk and -ctv)
N_PROMPT=512               # prefill tokens for llama-bench
N_GEN=128                  # generation tokens for llama-bench
REPETITIONS=3              # llama-bench runs per test (averaged)
GPU_LAYERS=99
CPU_THREADS=8
CTX_SIZE=8192              # context used for the memory estimate (and ppl)
RUN_PPL="${RUN_PPL:-0}"    # 1 = also run perplexity (slow)
PPL_DATASET="${PPL_DATASET:-$MODEL_DIR/wikitext-2-raw/wiki.test.raw}"
REPORT="$(dirname "$0")/kv-sweep-results.md"

# Model KV geometry for the memory estimate (Llama-3.1-8B defaults — adjust per model).
N_LAYER=32
N_KV_HEAD=8
HEAD_DIM=128

# Approximate bits-per-element per ggml type (includes block scale overhead).
bits_for() {
    case "$1" in
        f32) echo 32 ;; f16|bf16) echo 16 ;; q8_0) echo 8.5 ;;
        q5_1) echo 6 ;; q5_0) echo 5.5 ;; q4_1) echo 5 ;;
        q4_0|iq4_nl) echo 4.5 ;;
        *) echo "" ;;   # unknown -> caller logs and skips estimate
    esac
}

# ====================== PREFLIGHT ======================
for bin in "$BENCH_BIN" "$PPL_BIN"; do
    if [ ! -f "$bin" ]; then
        echo "❌ Error: binary not found at $bin" >&2
        echo "   Build llama.cpp into /Users/Shared/llama/llama.cpp/build/bin/" >&2
        exit 1
    fi
done
if [ ! -f "$MODEL_PATH" ]; then
    echo "❌ Error: Model not found at $MODEL_PATH" >&2
    ls -lh "$MODEL_DIR/" 2>/dev/null >&2 || echo "   (models folder empty)" >&2
    exit 1
fi
if [ "$RUN_PPL" = "1" ] && [ ! -f "$PPL_DATASET" ]; then
    echo "❌ Error: RUN_PPL=1 but dataset not found at $PPL_DATASET" >&2
    echo "   Run ./start-perplexity.sh once to auto-download wikitext-2, or set PPL_DATASET." >&2
    exit 1
fi

echo "=== KV-cache quantization sweep ==="
echo "Model     : $MODEL_PATH"
echo "Types     : ${KV_TYPES[*]}"
echo "Bench     : pp$N_PROMPT / tg$N_GEN, reps=$REPETITIONS, fa=on"
echo "Memory ctx: $CTX_SIZE (layers=$N_LAYER kv_heads=$N_KV_HEAD head_dim=$HEAD_DIM)"
echo "Perplexity: $([ "$RUN_PPL" = "1" ] && echo "on ($PPL_DATASET)" || echo "off (RUN_PPL=1 to enable)")"
echo "==================================="

# KV memory estimate (GiB) for a type: 2 (K+V) * layers * ctx * kv_heads * head_dim * bits/8.
kv_mem_gib() {
    local bits; bits="$(bits_for "$1")"
    [ -z "$bits" ] && { echo "n/a"; return; }
    awk -v b="$bits" -v L="$N_LAYER" -v c="$CTX_SIZE" -v h="$N_KV_HEAD" -v d="$HEAD_DIM" \
        'BEGIN { printf "%.2f", (2*L*c*h*d*b/8)/(1024*1024*1024) }'
}

# Run llama-bench for one KV type; echo "<prefill_ts> <gen_ts>" (or "n/a n/a").
run_bench() {
    local kv="$1" csv pp_ts tg_ts
    if ! csv="$("$BENCH_BIN" -m "$MODEL_PATH" -p "$N_PROMPT" -n "$N_GEN" \
                    --n-gpu-layers "$GPU_LAYERS" -t "$CPU_THREADS" \
                    -fa 1 -ctk "$kv" -ctv "$kv" -r "$REPETITIONS" -o csv 2>/dev/null)"; then
        echo "❌ Error: llama-bench failed for KV=$kv" >&2
        echo "n/a n/a"; return
    fi
    # CSV columns vary by build; locate n_gen and avg_ts by header name.
    pp_ts="$(awk -F',' 'NR==1{for(i=1;i<=NF;i++){gsub(/"/,"",$i);if($i=="n_gen")g=i;if($i=="avg_ts")a=i}}
                        NR>1{gsub(/"/,"",$g);gsub(/"/,"",$a);if($g==0)print $a}' <<<"$csv" | head -1)"
    tg_ts="$(awk -F',' 'NR==1{for(i=1;i<=NF;i++){gsub(/"/,"",$i);if($i=="n_gen")g=i;if($i=="avg_ts")a=i}}
                        NR>1{gsub(/"/,"",$g);gsub(/"/,"",$a);if($g>0)print $a}' <<<"$csv" | head -1)"
    echo "${pp_ts:-n/a} ${tg_ts:-n/a}"
}

# Run llama-perplexity for one KV type; echo PPL value (or "n/a").
run_ppl() {
    local kv="$1" out ppl
    if ! out="$("$PPL_BIN" -m "$MODEL_PATH" -f "$PPL_DATASET" -c "$CTX_SIZE" \
                    --n-gpu-layers "$GPU_LAYERS" -t "$CPU_THREADS" \
                    -fa 1 -ctk "$kv" -ctv "$kv" 2>&1)"; then
        echo "❌ Error: llama-perplexity failed for KV=$kv" >&2
        echo "n/a"; return
    fi
    ppl="$(grep -Eo 'Final estimate: PPL = [0-9.]+' <<<"$out" | grep -Eo '[0-9.]+$' | head -1)"
    echo "${ppl:-n/a}"
}

# ====================== SWEEP ======================
{
    echo "# KV-cache quantization sweep"
    echo
    echo "Model: \`$MODEL_NAME\`  •  bench pp$N_PROMPT/tg$N_GEN reps=$REPETITIONS, fa=on  •  mem ctx=$CTX_SIZE"
    echo "Date: $(date +%Y-%m-%d)"
    echo
    echo "| KV type | prefill t/s | gen t/s | KV mem (GiB) | perplexity |"
    echo "|---------|------------:|--------:|-------------:|-----------:|"
} | tee "$REPORT"

for kv in "${KV_TYPES[@]}"; do
    if [ -z "$(bits_for "$kv")" ]; then
        echo "⚠️  Unknown KV type '$kv' — skipping." >&2
        continue
    fi
    echo "▶ Benchmarking KV=$kv ..." >&2
    read -r pp tg < <(run_bench "$kv")
    mem="$(kv_mem_gib "$kv")"
    if [ "$RUN_PPL" = "1" ]; then
        echo "▶ Perplexity KV=$kv (slow) ..." >&2
        ppl="$(run_ppl "$kv")"
    else
        ppl="—"
    fi
    printf "| %-7s | %11s | %7s | %12s | %10s |\n" "$kv" "$pp" "$tg" "$mem" "$ppl" | tee -a "$REPORT"
done

echo
echo "✅ Sweep complete. Table written to $REPORT"
