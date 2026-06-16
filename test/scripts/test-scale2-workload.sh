#!/usr/bin/env bash
# SCALE-2 load workload — SCALE-1 cases + P3 long-context (KV prefill stress).
set -euo pipefail
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${FHS}/var/lib/cofiswarm/deploy/scale2-workload.json"
DISPATCH="${DISPATCH_URL:-http://127.0.0.1:8010}"
P3_FILE="${SCALE_PROMPT_P3_FILE:-$(dirname "$0")/fixtures/scale-prompt-p3.txt}"
mkdir -p "$(dirname "$OUT")"
TS="$(date -u +"%Y-%m-%dT%H:%MZ")"
export COFISWARM_MODE_EXECUTE_TIMEOUT="${COFISWARM_MODE_EXECUTE_TIMEOUT:-600}"

[[ -f "$P3_FILE" ]] || { echo "fail: missing P3 fixture $P3_FILE" >&2; exit 1; }

if ! curl -sf --max-time 5 "${DISPATCH}/api/health" >/dev/null; then
  echo "fail: dispatch not reachable at ${DISPATCH}" >&2
  exit 1
fi

# Run baseline workload first (updates scale0-workload.json)
"$(dirname "$0")/test-scale0-workload.sh"

python3 - "$DISPATCH" "$P3_FILE" "$OUT" "$TS" <<'PY'
import json, sys, time, urllib.request, concurrent.futures

dispatch, p3_path, out_path, ts = sys.argv[1:5]
p3 = open(p3_path).read().strip()
SLOT_MGR = "http://127.0.0.1:8013/api/pressure"

def peak_kv():
    try:
        with urllib.request.urlopen(SLOT_MGR, timeout=5) as r:
            data = json.loads(r.read().decode())
        vals = [e["usage"] for e in data if isinstance(e.get("usage"), (int, float))]
        return round(max(vals), 4) if vals else None
    except Exception:
        return None

def run_case(mode, pid, prompt, mode_config=None):
    body = {"prompt": prompt, "mode": mode}
    if mode_config:
        body["mode_config"] = mode_config
    req = urllib.request.Request(
        f"{dispatch}/api/architect",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    t0 = time.monotonic()
    with urllib.request.urlopen(req, timeout=600) as resp:
        raw = json.loads(resp.read().decode())
    wall = round(time.monotonic() - t0, 2)
    meta = raw.get("meta") or {}
    note = "infer" if meta.get("infer") else ("relay" if meta.get("relay") else meta.get("stub") and "stub" or "")
    final = raw.get("final") or ""
    ok = bool(final.strip()) or bool(raw.get("agents"))
    return {
        "mode": mode, "prompt": pid, "pass": ok,
        "wall_s": wall, "kv_pressure": peak_kv(), "notes": note,
    }

extra = [
    ("flat", "P3", p3, {"agents": ["architect"], "max_tokens": 512}),
    ("pipeline", "P3", p3, {"agents": ["architect", "programmer", "tester"], "max_tokens": 384}),
    ("cascade", "P3", p3, {"max_tokens": 384}),
]
rows = []
for mode, pid, prompt, cfg in extra:
    try:
        rows.append(run_case(mode, pid, prompt, cfg))
    except Exception as exc:
        rows.append({"mode": mode, "prompt": pid, "pass": False, "wall_s": None, "kv_pressure": None, "notes": str(exc)})

# Concurrent flat P1 (session load)
p1 = "What is a binary search tree?"
try:
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
        futs = [ex.submit(run_case, "flat", "P1-concurrent", p1, {"agents": ["architect", "programmer"]}) for _ in range(2)]
        for f in concurrent.futures.as_completed(futs):
            rows.append(f.result())
except Exception as exc:
    rows.append({"mode": "flat", "prompt": "P1-concurrent", "pass": False, "notes": str(exc)})

base_path = out_path.replace("scale2", "scale0")
base = json.load(open(base_path))
all_rows = base.get("results", []) + rows
payload = {"ts": ts, "dispatch": dispatch, "sprint": "SCALE-2", "results": all_rows}
with open(out_path, "w") as f:
    json.dump(payload, f, indent=2)
failed = [r for r in all_rows if not r.get("pass")]
peaks = [r["kv_pressure"] for r in all_rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
print(f"ok: scale2 workload → {out_path} ({len(all_rows)-len(failed)}/{len(all_rows)} pass, peak kv {max_p:.3f})")
sys.exit(1 if failed else 0)
PY
