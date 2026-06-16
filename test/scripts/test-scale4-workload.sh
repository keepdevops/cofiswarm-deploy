#!/usr/bin/env bash
# SCALE-4 load — SCALE-3 + KV quant audit + dual concurrent pipeline.
set -euo pipefail
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${FHS}/var/lib/cofiswarm/deploy/scale4-workload.json"
SWARM="${COFISWARM_SWARM_CONFIG:-${FHS}/etc/cofiswarm/config/swarm-config.json}"
DISPATCH="${DISPATCH_URL:-http://127.0.0.1:8010}"
export COFISWARM_MODE_EXECUTE_TIMEOUT="${COFISWARM_MODE_EXECUTE_TIMEOUT:-600}"

chmod +x "$(dirname "$0")/test-scale3-workload.sh"
"$(dirname "$0")/test-scale3-workload.sh"

python3 - "$DISPATCH" "$SWARM" "$OUT" <<'PY'
import json, sys, time, urllib.request, concurrent.futures, os

dispatch, swarm_path, out_path = sys.argv[1:4]
SLOT_MGR = "http://127.0.0.1:8013/api/pressure"
P4 = "This function returns None on empty input — fix it.\ndef first(xs):\n    return xs[0] if xs else None"

def peak_kv():
    try:
        with urllib.request.urlopen(SLOT_MGR, timeout=5) as r:
            data = json.loads(r.read().decode())
        vals = [e["usage"] for e in data if isinstance(e.get("usage"), (int, float))]
        return round(max(vals), 4) if vals else None
    except Exception:
        return None

def kv_audit(path):
    doc = json.load(open(path))
    rows = []
    ok = True
    for a in doc.get("agents", []):
        args = a.get("extra_args") or []
        kt = kv = None
        for i, x in enumerate(args):
            if x == "--cache-type-k" and i + 1 < len(args):
                kt = args[i + 1]
            if x == "--cache-type-v" and i + 1 < len(args):
                kv = args[i + 1]
        row = {"agent": a.get("name"), "cache_type_k": kt, "cache_type_v": kv}
        if a.get("engine") != "llama":
            row["pass"] = True
        elif kt is None or kv is None:
            row["pass"] = False
            ok = False
        else:
            row["pass"] = True
        rows.append(row)
    return {"pass": ok, "agents": rows}

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

scale3_path = out_path.replace("scale4", "scale3")
base = json.load(open(scale3_path))
extra = []
try:
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
        futs = [
            ex.submit(run_case_retry, "pipeline", "P4-pipeline-dual", P4, {"max_tokens": 128})
            for _ in range(2)
        ]
        for f in concurrent.futures.as_completed(futs):
            extra.append(f.result())
except Exception as exc:
    extra.append({"mode": "pipeline", "prompt": "P4-pipeline-dual", "pass": False, "notes": str(exc)})

audit = kv_audit(swarm_path)
all_rows = base.get("results", []) + extra
payload = {
    "ts": time.strftime("%Y-%m-%dT%H:%MZ", time.gmtime()),
    "dispatch": dispatch,
    "sprint": "SCALE-4",
    "kv_audit": audit,
    "results": all_rows,
}
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w") as f:
    json.dump(payload, f, indent=2)
failed = [r for r in all_rows if not r.get("pass")]
peaks = [r["kv_pressure"] for r in all_rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
print(f"ok: scale4 workload → {out_path} ({len(all_rows)-len(failed)}/{len(all_rows)} pass, kv audit {audit['pass']}, peak kv {max_p:.3f})")
sys.exit(1 if failed or not audit["pass"] else 0)
PY
