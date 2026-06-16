#!/usr/bin/env bash
# Live configure spawn (llama agents). Slow: 1–4 min. Requires CONFIGURE_LIVE=1.
set -euo pipefail
[[ "${CONFIGURE_LIVE:-}" == "1" ]] || {
  echo "skip: set CONFIGURE_LIVE=1 to spawn llama-server processes"
  exit 0
}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
SWARM="${FHS}/etc/cofiswarm/config/swarm-config.json"
CFG="${CONFIGURE_URL:-http://127.0.0.1:8017}"
DEADLINE="${CONFIGURE_LIVE_SECS:-600}"
SLOTS="${FHS}/var/lib/cofiswarm/models/llama/slots"

"${ROOT}/test/scripts/test-configure-gate.sh"
mkdir -p "$SLOTS"

status_json() { curl -sf --max-time 10 "${CFG}/api/configure/status" 2>/dev/null || echo '{}'; }

if python3 -c "import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if d.get('active') else 1)" "$(status_json)"; then
  echo "note: configure already active — polling status"
else
  body="$(python3 -c "
import json
doc=json.load(open('$SWARM'))
agents=[a for a in doc['agents'] if (a.get('backend') or a.get('engine') or 'llama')=='llama']
print(json.dumps({'agents': agents}))
")"
  # Short client timeout: server keeps spawning; poll /api/configure/status (same as UI).
  curl -sS -m 5 -X POST "${CFG}/api/configure" \
    -H 'Content-Type: application/json' \
    -d "$body" >/dev/null 2>&1 || true
  sleep 1
fi

end=$((SECONDS + DEADLINE))
while (( SECONDS < end )); do
  st="$(status_json)"
  if python3 -c "
import json, sys
d=json.loads(sys.argv[1])
ports=d.get('ports') or {}
errs=[p for p,s in ports.items() if s=='error']
ready=[p for p,s in ports.items() if s=='ready']
pending=[p for p,s in ports.items() if s not in ('ready','error')]
if errs:
    print('fail: configure ports error:', ','.join(errs), file=sys.stderr)
    sys.exit(1)
if ports and not pending:
    print('ok: configure ports ready:', ','.join(sorted(ready, key=int)))
    sys.exit(0)
if ports:
    print('waiting:', ports)
sys.exit(2)
" "$st"; then
    break
  fi
  sleep 5
done
if (( SECONDS >= end )); then
  echo "fail: configure timeout after ${DEADLINE}s (check ${FHS}/var/log/cofiswarm/launcher/)" >&2
  exit 1
fi

"${ROOT}/test/scripts/test-scale0-probe.sh"
python3 -c "
import json, sys
p=json.load(open('${FHS}/var/lib/cofiswarm/deploy/scale0-pressure.json'))
llama=[e for e in p.get('pressure',[]) if e.get('backend')=='llama']
ok=[e for e in llama if e.get('ok')]
print(f'ok: configure live — {len(ok)}/{len(llama)} llama endpoints reporting pressure')
sys.exit(0 if len(ok) == len(llama) and llama else 1)
"
