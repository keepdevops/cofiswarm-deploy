#!/bin/bash
# slot-cache.sh - persist a llama-server slot's KV cache to disk and reload it.
#
# Unlike the in-memory prompt cache (which dies with the server), this saves a
# primed slot's KV state to a file via the server's /slots endpoints, so a long
# system prompt survives a restart and reloads in ~ms instead of being recomputed.
#
# REQUIRES the server to be launched with --slot-save-path DIR (and --slots for
# `status`/`list`). start-kvquant.sh now does this by default.
#
# Endpoints used (llama.cpp llama-server):
#   POST /slots/{id}?action=save     body {"filename":"NAME.bin"}
#   POST /slots/{id}?action=restore  body {"filename":"NAME.bin"}
#   POST /slots/{id}?action=erase
#   GET  /slots                      (slot states; needs --slots)
#
# Usage:
#   ./slot-cache.sh save    <name> [slot]   # dump slot KV -> SLOT_SAVE_PATH/<name>.bin
#   ./slot-cache.sh restore <name> [slot]   # load <name>.bin into slot
#   ./slot-cache.sh erase   [slot]          # clear a slot's KV cache
#   ./slot-cache.sh list                    # list saved KV files on disk
#   ./slot-cache.sh status                  # server health + per-slot usage

set -euo pipefail

# ====================== CONFIG ======================
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8095}"
API_KEY="${API_KEY:-}"   # must match the server's --api-key, if any
SLOT_SAVE_PATH="${SLOT_SAVE_PATH:-/Users/caribou/test-llama/kv-slots}"
FORCE="${FORCE:-0}"      # 1 = bypass the provenance guard (risk: corrupt KV)

BASE="http://$HOST:$PORT"
SERVER_DESC="$SLOT_SAVE_PATH/.server-kv.env"   # KV types, written by start-kvquant.sh

usage() {
    # Print the header comment block (everything between the shebang and `set -euo`).
    sed -n '2,/^set -euo/p' "$0" | sed '/^set -euo/d; s/^# \{0,1\}//'
    exit "${1:-0}"
}

# curl wrapper: fail loudly on HTTP errors, attach auth when configured.
api() {
    local method="$1" url="$2" body="${3:-}"
    local args=( -sS -f -X "$method" "$url" )
    [ -n "$API_KEY" ] && args+=( -H "Authorization: Bearer $API_KEY" )
    if [ -n "$body" ]; then
        args+=( -H "Content-Type: application/json" -d "$body" )
    fi
    if ! curl "${args[@]}"; then
        echo "❌ Error: request failed: $method $url" >&2
        echo "   Is the server up (./start-kvquant.sh) and started with --slot-save-path?" >&2
        exit 1
    fi
}

# Live "<model_path>|<n_ctx>" from the server (authoritative for model + context).
server_props() {
    api GET "$BASE/props" | python3 -c \
'import sys,json
d=json.load(sys.stdin)
print(d.get("model_path","")+"|"+str(d.get("default_generation_settings",{}).get("n_ctx","")))'
}

# "<kv_k>|<kv_v>" from the launcher descriptor; "|" if it is missing.
server_kv_types() {
    [ -f "$SERVER_DESC" ] || { echo "|"; return; }
    local k v
    k="$(grep -E '^KV_TYPE_K=' "$SERVER_DESC" | head -1 | cut -d= -f2-)"
    v="$(grep -E '^KV_TYPE_V=' "$SERVER_DESC" | head -1 | cut -d= -f2-)"
    echo "$k|$v"
}

# Write the provenance sidecar next to a saved KV blob.
write_sidecar() {
    local meta="$1" props kv
    props="$(server_props)"; kv="$(server_kv_types)"
    {
        echo "MODEL=${props%%|*}"
        echo "N_CTX=${props##*|}"
        echo "KV_K=${kv%%|*}"
        echo "KV_V=${kv##*|}"
        echo "SAVED=$(date +%Y-%m-%dT%H:%M:%S)"
    } > "$meta"
}

# Refuse to restore a blob whose model / KV-type / context no longer matches the
# running server (would corrupt the KV cache). FORCE=1 overrides. Fails loudly.
verify_sidecar() {
    local meta="$1"
    if [ ! -f "$meta" ]; then
        echo "⚠️  No provenance sidecar at $meta — cannot verify model/KV match." >&2
        [ "$FORCE" = "1" ] && { echo "   FORCE=1 set; restoring anyway." >&2; return; }
        echo "   Refusing to restore. Re-run with FORCE=1 to override (risk: corrupt KV)." >&2
        exit 1
    fi
    local s_model s_ctx s_kk s_kvv props c_model c_ctx kv c_kk c_kvv mismatch=0
    s_model="$(grep -E '^MODEL=' "$meta" | cut -d= -f2-)"
    s_ctx="$(grep -E '^N_CTX=' "$meta" | cut -d= -f2-)"
    s_kk="$(grep -E '^KV_K=' "$meta" | cut -d= -f2-)"
    s_kvv="$(grep -E '^KV_V=' "$meta" | cut -d= -f2-)"
    props="$(server_props)"; c_model="${props%%|*}"; c_ctx="${props##*|}"
    kv="$(server_kv_types)"; c_kk="${kv%%|*}"; c_kvv="${kv##*|}"

    [ "$s_model" != "$c_model" ] && { echo "❌ Model mismatch: saved '$s_model' vs server '$c_model'" >&2; mismatch=1; }
    if [ -z "$c_kk" ]; then
        echo "⚠️  Server KV type unknown (no $SERVER_DESC) — KV-type check skipped." >&2
    else
        [ "$s_kk" != "$c_kk" ]   && { echo "❌ KV-K mismatch: saved '$s_kk' vs server '$c_kk'" >&2; mismatch=1; }
        [ "$s_kvv" != "$c_kvv" ] && { echo "❌ KV-V mismatch: saved '$s_kvv' vs server '$c_kvv'" >&2; mismatch=1; }
    fi
    if [ -n "$s_ctx" ] && [ -n "$c_ctx" ] && [ "$c_ctx" -lt "$s_ctx" ] 2>/dev/null; then
        echo "❌ Context too small: blob needs $s_ctx tokens, server has $c_ctx" >&2; mismatch=1
    fi
    if [ "$mismatch" = "1" ]; then
        [ "$FORCE" = "1" ] && { echo "   FORCE=1 set; restoring despite mismatch." >&2; return; }
        echo "   Refusing to restore (would corrupt KV). Re-run with FORCE=1 to override." >&2
        exit 1
    fi
    echo "🔒 Provenance OK: model + KV types match."
}

# Reject path traversal / nested names before the server does (fail early).
validate_name() {
    local name="$1"
    if [ -z "$name" ]; then
        echo "❌ Error: missing <name> for KV cache file." >&2
        exit 1
    fi
    case "$name" in
        */*|..*|*..) echo "❌ Error: <name> must be a bare filename, got '$name'." >&2; exit 1 ;;
    esac
}

# Validate slot id is a non-negative integer.
validate_slot() {
    case "$1" in
        ''|*[!0-9]*) echo "❌ Error: slot id must be a non-negative integer, got '$1'." >&2; exit 1 ;;
    esac
}

ACTION="${1:-}"
[ -z "$ACTION" ] && usage 1

# Confirm the server is reachable for every action except local `list`.
if [ "$ACTION" != "list" ]; then
    if ! curl -sS -f -o /dev/null "$BASE/health" 2>/dev/null; then
        echo "❌ Error: server not reachable at $BASE/health" >&2
        echo "   Start it first: ./start-kvquant.sh" >&2
        exit 1
    fi
fi

case "$ACTION" in
    save)
        NAME="${2:-}"; SLOT="${3:-0}"
        validate_name "$NAME"; validate_slot "$SLOT"
        FILE="$NAME.bin"
        echo "💾 Saving slot $SLOT KV cache -> $SLOT_SAVE_PATH/$FILE"
        api POST "$BASE/slots/$SLOT?action=save" "{\"filename\":\"$FILE\"}"
        echo
        write_sidecar "$SLOT_SAVE_PATH/$FILE.meta"
        echo "🔒 Provenance recorded -> $FILE.meta (model + KV type)"
        echo "✅ Saved. Restore later with: ./slot-cache.sh restore $NAME $SLOT"
        ;;
    restore)
        NAME="${2:-}"; SLOT="${3:-0}"
        validate_name "$NAME"; validate_slot "$SLOT"
        FILE="$NAME.bin"
        if [ ! -f "$SLOT_SAVE_PATH/$FILE" ]; then
            echo "❌ Error: $SLOT_SAVE_PATH/$FILE not found. Run 'list' to see saved files." >&2
            exit 1
        fi
        verify_sidecar "$SLOT_SAVE_PATH/$FILE.meta"
        echo "♻️  Restoring $FILE -> slot $SLOT"
        api POST "$BASE/slots/$SLOT?action=restore" "{\"filename\":\"$FILE\"}"
        echo
        echo "✅ Restored. The slot's KV cache is primed; next request reuses it."
        ;;
    erase)
        SLOT="${2:-0}"
        validate_slot "$SLOT"
        echo "🧹 Erasing KV cache in slot $SLOT"
        api POST "$BASE/slots/$SLOT?action=erase"
        echo
        echo "✅ Slot $SLOT cleared."
        ;;
    list)
        echo "=== Saved KV cache files in $SLOT_SAVE_PATH ==="
        if [ ! -d "$SLOT_SAVE_PATH" ]; then
            echo "(directory does not exist yet — nothing saved)"
            exit 0
        fi
        shopt -s nullglob
        blobs=("$SLOT_SAVE_PATH"/*.bin)
        if [ ${#blobs[@]} -eq 0 ]; then
            echo "(no .bin KV files saved yet)"
        fi
        for b in "${blobs[@]}"; do
            size="$(ls -lh "$b" | awk '{print $5}')"
            meta="$b.meta"
            if [ -f "$meta" ]; then
                model="$(grep -E '^MODEL=' "$meta" | cut -d= -f2- | xargs basename 2>/dev/null)"
                kk="$(grep -E '^KV_K=' "$meta" | cut -d= -f2-)"
                kvv="$(grep -E '^KV_V=' "$meta" | cut -d= -f2-)"
                printf "  %-22s %6s  [%s, KV=%s/%s]\n" "$(basename "$b")" "$size" "$model" "$kk" "$kvv"
            else
                printf "  %-22s %6s  [⚠️ no provenance sidecar]\n" "$(basename "$b")" "$size"
            fi
        done
        ;;
    status)
        echo "=== Server $BASE — slot status ==="
        if ! api GET "$BASE/slots"; then
            echo "ℹ️  /slots returned nothing; ensure the server was started with --slots." >&2
        fi
        echo
        ;;
    -h|--help|help)
        usage 0
        ;;
    *)
        echo "❌ Error: unknown action '$ACTION'." >&2
        usage 1
        ;;
esac
