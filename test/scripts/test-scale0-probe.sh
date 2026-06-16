#!/usr/bin/env bash
# Live SCALE-0 probe — pressure snapshot from slot-manager (or legacy coordinator).
set -euo pipefail
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${FHS}/var/lib/cofiswarm/deploy/scale0-pressure.json"
mkdir -p "$(dirname "$OUT")"
TS="$(date -u +"%Y-%m-%dT%H:%MZ")"
if curl -sf --max-time 3 http://127.0.0.1:8013/api/pressure -o "${OUT}.tmp"; then
  SRC="slot-manager:8013"
elif curl -sf --max-time 3 http://127.0.0.1:8000/api/pressure -o "${OUT}.tmp"; then
  SRC="coordinator-legacy:8000"
else
  echo '{"error":"no pressure endpoint"}' > "${OUT}.tmp"
  SRC="none"
fi
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); json.dump({'ts':'${TS}','source':'${SRC}','pressure':d}, open(sys.argv[2],'w'), indent=2)" "${OUT}.tmp" "$OUT"
rm -f "${OUT}.tmp"
echo "ok: scale0 pressure → $OUT ($SRC)"
