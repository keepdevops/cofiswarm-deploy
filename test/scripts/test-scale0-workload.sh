#!/usr/bin/env bash
# SCALE-0 nominal workload — dispatch :8010 (P1 all modes + P2 flat/pipeline/cascade + P4 router).
set -euo pipefail
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${FHS}/var/lib/cofiswarm/deploy/scale0-workload.json"
DISPATCH="${DISPATCH_URL:-http://127.0.0.1:8010}"
P1="${SCALE_PROMPT_P1:-What is a binary search tree?}"
P2="${SCALE_PROMPT_P2:-Write a Python LRU cache class.}"
P4="${SCALE_PROMPT_P4:-This function returns None on empty input — fix it. def first(xs): return xs[0] if xs else None}"
mkdir -p "$(dirname "$OUT")"
TS="$(date -u +"%Y-%m-%dT%H:%MZ")"

if ! curl -sf --max-time 5 "${DISPATCH}/api/health" >/dev/null; then
  echo "fail: dispatch not reachable at ${DISPATCH} (run make up; wait for ready: dispatch)" >&2
  exit 1
fi

python3 - "$DISPATCH" "$P1" "$P2" "$P4" "$OUT" "$TS" <<'PY'
import json, sys, time, urllib.request

dispatch, p1, p2, p4, out_path, ts = sys.argv[1:7]
cases = [
    ("flat", "P1", p1), ("pipeline", "P1", p1), ("cascade", "P1", p1), ("router", "P1", p1),
    ("flat", "P2", p2), ("pipeline", "P2", p2), ("cascade", "P2", p2),
    ("router", "P4", p4),
]
rows = []
SLOT_MGR = "http://127.0.0.1:8013/api/pressure"

def peak_kv():
    try:
        with urllib.request.urlopen(SLOT_MGR, timeout=5) as r:
            data = json.loads(r.read().decode())
        vals = [e["usage"] for e in data if isinstance(e.get("usage"), (int, float))]
        return round(max(vals), 4) if vals else None
    except Exception:
        return None

for mode, pid, prompt in cases:
    body = json.dumps({"prompt": prompt, "mode": mode}).encode()
    req = urllib.request.Request(
        f"{dispatch}/api/architect", data=body,
        headers={"Content-Type": "application/json"}, method="POST",
    )
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            raw = json.loads(resp.read().decode())
        wall = round(time.monotonic() - t0, 2)
        final = raw.get("final") or ""
        ok = bool(final.strip()) or bool(raw.get("agents"))
        meta = raw.get("meta") or {}
        if meta.get("infer"):
            note = "infer"
        elif meta.get("relay"):
            note = "relay"
        elif meta.get("stub"):
            note = "stub"
        else:
            note = ""
        rows.append({
            "mode": mode, "prompt": pid, "pass": ok,
            "wall_s": wall, "kv_pressure": peak_kv(), "notes": note,
        })
    except Exception as exc:
        rows.append({
            "mode": mode, "prompt": pid, "pass": False,
            "wall_s": None, "kv_pressure": None, "notes": str(exc),
        })

payload = {"ts": ts, "dispatch": dispatch, "results": rows}
with open(out_path, "w") as f:
    json.dump(payload, f, indent=2)
failed = [r for r in rows if not r["pass"]]
print(f"ok: scale0 workload → {out_path} ({len(rows) - len(failed)}/{len(rows)} pass)")
sys.exit(1 if failed else 0)
PY
