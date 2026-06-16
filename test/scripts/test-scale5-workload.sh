#!/usr/bin/env bash
# SCALE-5 load — SCALE-4 + triple concurrent cascade + 4-way mixed-mode burst.
set -euo pipefail
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${FHS}/var/lib/cofiswarm/deploy/scale5-workload.json"
DISPATCH="${DISPATCH_URL:-http://127.0.0.1:8010}"
export COFISWARM_MODE_EXECUTE_TIMEOUT="${COFISWARM_MODE_EXECUTE_TIMEOUT:-600}"

chmod +x "$(dirname "$0")/test-scale4-workload.sh"
"$(dirname "$0")/test-scale4-workload.sh"

python3 - "$DISPATCH" "$OUT" <<'PY'
import json, sys, time, urllib.request, concurrent.futures, os

dispatch, out_path = sys.argv[1:3]
SLOT_MGR = "http://127.0.0.1:8013/api/pressure"
P4 = "This function returns None on empty input — fix it.\ndef first(xs):\n    return xs[0] if xs else None"
P2 = "Write a Python LRU cache class with get, put, and O(1) amortized complexity."

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
    note = "infer" if meta.get("infer") else ("relay" if meta.get("relay") else "stub")
    ok = bool((raw.get("final") or "").strip()) or bool(raw.get("agents"))
    return {"mode": mode, "prompt": pid, "pass": ok, "wall_s": wall, "kv_pressure": peak_kv(), "notes": note}

def run_case_retry(mode, pid, prompt, mode_config=None, attempts=3):
    last = None
    for i in range(attempts):
        try:
            last = run_case(mode, pid, prompt, mode_config)
            if last.get("pass"):
                return last
        except Exception as exc:
            last = {"mode": mode, "prompt": pid, "pass": False, "notes": str(exc)}
        if i + 1 < attempts:
            time.sleep(3)
    return last

scale4_path = out_path.replace("scale5", "scale4")
base = json.load(open(scale4_path))
extra = []
try:
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:
        futs = [
            ex.submit(
                run_case_retry, "cascade", "P4-cascade-triple", P4,
                {"agents": ["architect", "programmer"], "max_tokens": 96},
            )
            for _ in range(3)
        ]
        for f in concurrent.futures.as_completed(futs):
            extra.append(f.result())
except Exception as exc:
    extra.append({"mode": "cascade", "prompt": "P4-cascade-triple", "pass": False, "notes": str(exc)})

try:
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
        futs = [
            ex.submit(run_case_retry, "flat", "P2-mixed-burst", P2, {"max_tokens": 128}),
            ex.submit(run_case_retry, "pipeline", "P2-mixed-burst", P2, {"max_tokens": 128}),
            ex.submit(run_case_retry, "cascade", "P2-mixed-burst", P2, {"agents": ["architect"], "max_tokens": 96}),
            ex.submit(run_case_retry, "router", "P2-mixed-burst", P2, {"max_tokens": 128}),
        ]
        for f in concurrent.futures.as_completed(futs):
            extra.append(f.result())
except Exception as exc:
    extra.append({"mode": "mixed", "prompt": "P2-mixed-burst", "pass": False, "notes": str(exc)})

all_rows = base.get("results", []) + extra
payload = {
    "ts": time.strftime("%Y-%m-%dT%H:%MZ", time.gmtime()),
    "dispatch": dispatch,
    "sprint": "SCALE-5",
    "load": {"cascade_triple": 3, "mixed_burst_modes": 4},
    "results": all_rows,
}
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w") as f:
    json.dump(payload, f, indent=2)
failed = [r for r in all_rows if not r.get("pass")]
peaks = [r["kv_pressure"] for r in all_rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
print(f"ok: scale5 workload → {out_path} ({len(all_rows)-len(failed)}/{len(all_rows)} pass, peak kv {max_p:.3f})")
sys.exit(1 if failed else 0)
PY
