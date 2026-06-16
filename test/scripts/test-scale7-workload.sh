#!/usr/bin/env bash
# SCALE-7 load — SCALE-5 + MLX pilot (retry) + ROSTER-full + pressure snapshot.
set -euo pipefail
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
OUT="${FHS}/var/lib/cofiswarm/deploy/scale7-workload.json"
SWARM="${COFISWARM_SWARM_CONFIG:-${FHS}/etc/cofiswarm/config/swarm-config.json}"
DISPATCH="${DISPATCH_URL:-http://127.0.0.1:8010}"
MLX_PORT="${MLX_SCOUT_PORT:-8083}"
export COFISWARM_MODE_EXECUTE_TIMEOUT="${COFISWARM_MODE_EXECUTE_TIMEOUT:-600}"

SCALE5_BASE="${FHS}/var/lib/cofiswarm/deploy/scale5-workload.json"
reuse=0
if [[ "${SCALE7_REUSE_BASE:-1}" == "1" ]] && [[ -f "$SCALE5_BASE" ]]; then
  if python3 - "$SCALE5_BASE" <<'PY'
import json, sys
w = json.load(open(sys.argv[1]))
rows = w.get("results") or []
sys.exit(0 if rows and all(r.get("pass") for r in rows) else 1)
PY
  then
    reuse=1
    echo "ok: reuse scale5-workload.json (SCALE7_REUSE_BASE=1, ${SCALE5_BASE##*/} all pass)"
  fi
fi

chmod +x "$(dirname "$0")/test-scale5-workload.sh" "$(dirname "$0")/test-scale0-probe.sh" "$(dirname "$0")/ensure-mlx-scout.sh"
if [[ "$reuse" != 1 ]]; then
  "$(dirname "$0")/test-scale5-workload.sh"
fi
"$(dirname "$0")/test-scale0-probe.sh"
"$(dirname "$0")/ensure-mlx-scout.sh"

python3 - "$DISPATCH" "$SWARM" "$OUT" "$MLX_PORT" "${FHS}/var/lib/cofiswarm/deploy/scale0-pressure.json" <<'PY'
import json, sys, time, urllib.request, concurrent.futures, os

dispatch, swarm_path, out_path, mlx_port, pressure_path = sys.argv[1:6]
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

def mlx_healthy():
    for url in (MLX_HEALTH, f"http://127.0.0.1:{mlx_port}/v1/models"):
        try:
            with urllib.request.urlopen(url, timeout=5) as r:
                if 200 <= r.status < 300:
                    return True
        except Exception:
            pass
    return False

def wait_mlx_healthy(deadline=60):
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

def run_single_agent(agent_name):
    body = {
        "prompt": "Reply with one word: OK",
        "mode": "flat",
        "mode_config": {"agents": [agent_name], "max_tokens": 16},
    }
    req = urllib.request.Request(
        f"{dispatch}/api/architect",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    t0 = time.monotonic()
    with urllib.request.urlopen(req, timeout=180) as resp:
        raw = json.loads(resp.read().decode())
    wall = round(time.monotonic() - t0, 2)
    agents = raw.get("agents") or {}
    out = agents.get(agent_name, "")
    ok = isinstance(out, str) and out.strip() and not out.strip().startswith("[unavailable")
    return ok, wall

def run_single_agent_retry(agent_name, attempts=4):
    for i in range(attempts):
        try:
            ok, wall = run_single_agent(agent_name)
            if ok:
                return ok, wall
        except Exception:
            pass
        if i + 1 < attempts:
            time.sleep(2)
    return False, 0.0

def run_roster_sequential(agent_names):
    agents_ok = []
    agents_fail = []
    walls = []
    for name in agent_names:
        ok, wall = run_single_agent_retry(name)
        if wall:
            walls.append(wall)
        if ok:
            agents_ok.append(name)
        else:
            agents_fail.append(name)
        time.sleep(0.5)
    wall = round(sum(walls), 2) if walls else None
    return {
        "mode": "flat", "prompt": "ROSTER-full", "pass": len(agents_ok) == len(agent_names),
        "wall_s": wall, "kv_pressure": peak_kv(),
        "notes": f"per-agent {len(agents_ok)}/{len(agent_names)}",
        "agents_ok": agents_ok, "agents_fail": agents_fail, "agents_expected": agent_names,
    }

doc = json.load(open(swarm_path))
all_names = sorted(a["name"] for a in doc.get("agents", []) if a.get("name"))
llama_names = sorted(
    a["name"] for a in doc.get("agents", [])
    if a.get("name") and (a.get("engine") or a.get("backend") or "llama") == "llama"
)
mlx_names = [n for n in all_names if n not in llama_names]

scale5_path = out_path.replace("scale7", "scale5")
base = json.load(open(scale5_path))
extra = []

if wait_mlx_healthy():
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
            futs = [ex.submit(mlx_chat, "What is a hash map?", 32) for _ in range(2)]
            for f in concurrent.futures.as_completed(futs):
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
else:
    extra.append({
        "mode": "mlx", "prompt": "MLX-health", "pass": False,
        "notes": f"port {mlx_port} down — start mlx_lm.server on :8083 before SCALE-7",
    })

try:
    extra.append(run_roster_sequential(llama_names))
except Exception as exc:
    extra.append({
        "mode": "flat", "prompt": "ROSTER-full", "pass": False,
        "notes": str(exc), "agents_expected": llama_names, "agents_ok": [],
    })

all_rows = base.get("results", []) + extra
roster_row = next((r for r in extra if r.get("prompt") == "ROSTER-full"), {})
mlx_ok = any(r.get("prompt") == "MLX-P1" and r.get("pass") for r in extra)
pressure = {}
if os.path.isfile(pressure_path):
    pressure = json.load(open(pressure_path))

payload = {
    "ts": time.strftime("%Y-%m-%dT%H:%MZ", time.gmtime()),
    "dispatch": dispatch,
    "sprint": "SCALE-7",
    "mlx_port": mlx_port,
    "roster": {
        "expected": len(all_names),
        "llama_expected": len(llama_names),
        "mlx_agents": mlx_names,
        "llama_ok": roster_row.get("agents_ok") or [],
        "llama_fail": roster_row.get("agents_fail") or [],
        "mlx_ok": mlx_ok,
        "all_names": all_names,
    },
    "pressure": pressure,
    "results": all_rows,
}
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w") as f:
    json.dump(payload, f, indent=2)
failed = [r for r in all_rows if not r.get("pass")]
peaks = [r["kv_pressure"] for r in all_rows if isinstance(r.get("kv_pressure"), (int, float))]
max_p = max(peaks) if peaks else 0.0
llama_got = len(roster_row.get("agents_ok") or [])
print(f"ok: scale7 workload → {out_path} ({len(all_rows)-len(failed)}/{len(all_rows)} pass, roster {llama_got}/{len(llama_names)} llama, mlx {mlx_ok}, peak kv {max_p:.3f})")
sys.exit(1 if failed else 0)
PY
