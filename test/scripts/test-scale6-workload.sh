#!/usr/bin/env bash
# SCALE-6 load — SCALE-5 + MLX scout pilot (TurboQuant 4bit lane).
set -euo pipefail
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${FHS}/var/lib/cofiswarm/deploy/scale6-workload.json"
SWARM="${COFISWARM_SWARM_CONFIG:-${FHS}/etc/cofiswarm/config/swarm-config.json}"
MLX_PORT="${MLX_SCOUT_PORT:-8083}"
export COFISWARM_MODE_EXECUTE_TIMEOUT="${COFISWARM_MODE_EXECUTE_TIMEOUT:-600}"

chmod +x "$(dirname "$0")/test-scale5-workload.sh"
"$(dirname "$0")/test-scale5-workload.sh"

python3 - "$SWARM" "$OUT" "$MLX_PORT" <<'PY'
import json, sys, time, urllib.request, concurrent.futures, os

swarm_path, out_path, mlx_port = sys.argv[1:4]
mlx_port = int(mlx_port)
SLOT_MGR = "http://127.0.0.1:8013/api/pressure"
MLX_URL = f"http://127.0.0.1:{mlx_port}/v1/chat/completions"
MLX_HEALTH = f"http://127.0.0.1:{mlx_port}/health"

def peak_kv():
    try:
        with urllib.request.urlopen(SLOT_MGR, timeout=5) as r:
            data = json.loads(r.read().decode())
        vals = [e["usage"] for e in data if isinstance(e.get("usage"), (int, float))]
        return round(max(vals), 4) if vals else None
    except Exception:
        return None

def mlx_audit(path):
    doc = json.load(open(path))
    scout = next((a for a in doc.get("agents", []) if a.get("name") == "mlx-scout"), None)
    if not scout:
        return {"pass": False, "error": "mlx-scout missing"}
    model = scout.get("model") or ""
    checks = {
        "engine_mlx": scout.get("engine") == "mlx",
        "port": scout.get("port") == mlx_port,
        "max_concurrency_1": scout.get("max_concurrency", 1) == 1,
        "quant_4bit": "4bit" in model.lower(),
    }
    return {"pass": all(checks.values()), "checks": checks, "model": model}

def mlx_healthy():
    for url in (MLX_HEALTH, f"http://127.0.0.1:{mlx_port}/v1/models"):
        try:
            with urllib.request.urlopen(url, timeout=5) as r:
                if 200 <= r.status < 300:
                    return True
        except Exception:
            pass
    return False

def wait_mlx_healthy(deadline=120):
    t0 = time.monotonic()
    while time.monotonic() - t0 < deadline:
        if mlx_healthy():
            return True
        time.sleep(2)
    return mlx_healthy()

def mlx_chat(prompt, max_tokens=64):
    body = json.dumps({
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
    }).encode()
    req = urllib.request.Request(
        MLX_URL, data=body,
        headers={"Content-Type": "application/json"}, method="POST",
    )
    t0 = time.monotonic()
    with urllib.request.urlopen(req, timeout=180) as resp:
        raw = json.loads(resp.read().decode())
    wall = round(time.monotonic() - t0, 2)
    choices = raw.get("choices") or []
    content = ""
    if choices:
        content = (choices[0].get("message") or {}).get("content") or ""
    return wall, bool(content.strip())

audit = mlx_audit(swarm_path)
scale5_path = out_path.replace("scale6", "scale5")
base = json.load(open(scale5_path))
extra = []

if not audit.get("pass"):
    extra.append({"mode": "mlx", "prompt": "MLX-audit", "pass": False, "notes": "mlx_audit"})
elif not wait_mlx_healthy():
    extra.append({"mode": "mlx", "prompt": "MLX-health", "pass": False, "notes": f"port {mlx_port} down after wait"})
else:
    try:
        wall, ok = mlx_chat("Summarize binary search trees in one sentence.", 48)
        extra.append({
            "mode": "mlx", "prompt": "MLX-P1", "pass": ok,
            "wall_s": wall, "kv_pressure": peak_kv(), "notes": "mlx-direct",
        })
    except Exception as exc:
        extra.append({"mode": "mlx", "prompt": "MLX-P1", "pass": False, "notes": str(exc)})
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
            futs = [
                ex.submit(mlx_chat, "What is a hash map?", 32)
                for _ in range(2)
            ]
            for i, f in enumerate(concurrent.futures.as_completed(futs)):
                try:
                    wall, ok = f.result()
                    extra.append({
                        "mode": "mlx", "prompt": "MLX-dual", "pass": ok,
                        "wall_s": wall, "kv_pressure": peak_kv(), "notes": "mlx-concurrent",
                    })
                except Exception as exc:
                    extra.append({"mode": "mlx", "prompt": "MLX-dual", "pass": False, "notes": str(exc)})
    except Exception as exc:
        extra.append({"mode": "mlx", "prompt": "MLX-dual", "pass": False, "notes": str(exc)})

all_rows = base.get("results", []) + extra
payload = {
    "ts": time.strftime("%Y-%m-%dT%H:%MZ", time.gmtime()),
    "sprint": "SCALE-6",
    "mlx_audit": audit,
    "mlx_port": mlx_port,
    "results": all_rows,
}
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w") as f:
    json.dump(payload, f, indent=2)
failed = [r for r in all_rows if not r.get("pass")]
peaks = [r["kv_pressure"] for r in all_rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
mlx_rows = [r for r in extra if r.get("mode") == "mlx"]
print(f"ok: scale6 workload → {out_path} ({len(all_rows)-len(failed)}/{len(all_rows)} pass, mlx audit {audit.get('pass')}, peak kv {max_p:.3f})")
sys.exit(1 if failed or not audit.get("pass") else 0)
PY
