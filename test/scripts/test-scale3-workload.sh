#!/usr/bin/env bash
# SCALE-3 load workload — SCALE-2 + heavier tokens + concurrent router.
set -euo pipefail
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${FHS}/var/lib/cofiswarm/deploy/scale3-workload.json"
DISPATCH="${DISPATCH_URL:-http://127.0.0.1:8010}"
P3_FILE="${SCALE_PROMPT_P3_FILE:-$(dirname "$0")/fixtures/scale-prompt-p3.txt}"
export COFISWARM_MODE_EXECUTE_TIMEOUT="${COFISWARM_MODE_EXECUTE_TIMEOUT:-600}"

"$(dirname "$0")/test-scale2-workload.sh"
[[ -f "$P3_FILE" ]] || { echo "fail: missing P3 fixture" >&2; exit 1; }

python3 - "$DISPATCH" "$P3_FILE" "$OUT" <<'PY'
import json, sys, time, urllib.request, concurrent.futures

dispatch, p3_path, out_path = sys.argv[1:4]
p3 = open(p3_path).read().strip()
p4 = "This function returns None on empty input — fix it.\ndef first(xs):\n    return xs[0] if xs else None"
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
        f"{dispatch}/api/architect", data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"}, method="POST",
    )
    t0 = time.monotonic()
    with urllib.request.urlopen(req, timeout=600) as resp:
        raw = json.loads(resp.read().decode())
    wall = round(time.monotonic() - t0, 2)
    meta = raw.get("meta") or {}
    note = "infer" if meta.get("infer") else ("relay" if meta.get("relay") else "stub")
    ok = bool((raw.get("final") or "").strip()) or bool(raw.get("agents"))
    return {"mode": mode, "prompt": pid, "pass": ok, "wall_s": wall, "kv_pressure": peak_kv(), "notes": note}

extra = []
for mode, cfg in [
    ("router", {"max_tokens": 384}),
    ("cascade", {"max_tokens": 384}),
    ("flat", {"agents": ["architect", "programmer", "debugger"], "max_tokens": 256}),
]:
    try:
        extra.append(run_case(mode, "P3-heavy", p3, cfg))
    except Exception as exc:
        extra.append({"mode": mode, "prompt": "P3-heavy", "pass": False, "notes": str(exc)})

try:
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:
        futs = [ex.submit(run_case, "router", "P4-concurrent", p4, {"max_tokens": 128}) for _ in range(3)]
        for f in concurrent.futures.as_completed(futs):
            extra.append(f.result())
except Exception as exc:
    extra.append({"mode": "router", "prompt": "P4-concurrent", "pass": False, "notes": str(exc)})

base = json.load(open(out_path.replace("scale3", "scale2")))
all_rows = base.get("results", []) + extra
payload = {"ts": time.strftime("%Y-%m-%dT%H:%MZ", time.gmtime()), "dispatch": dispatch, "sprint": "SCALE-3", "results": all_rows}
with open(out_path, "w") as f:
    json.dump(payload, f, indent=2)
failed = [r for r in all_rows if not r.get("pass")]
peaks = [r["kv_pressure"] for r in all_rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
print(f"ok: scale3 workload → {out_path} ({len(all_rows)-len(failed)}/{len(all_rows)} pass, peak kv {max_p:.3f})")
sys.exit(1 if failed else 0)
PY
