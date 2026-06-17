#!/usr/bin/env bash
# Sprint 53: Phase 6 optional repos — layout + static make test (no device stack).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"

python3 - "$ROOT/repos.json" "$REPOS" <<'PY'
import json, subprocess, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text())
repos_root = Path(sys.argv[2])
phase6 = [r for r in doc.get("repos") or [] if r.get("phase") == 6]
if len(phase6) < 6:
    raise SystemExit(f"fail: expected >=6 phase-6 repos, got {len(phase6)}")
bad = []
for r in phase6:
    name = r["name"]
    if r.get("required"):
        bad.append(f"{name}: phase 6 must be optional (required=false)")
    path = repos_root / name
    if not path.is_dir():
        bad.append(f"{name}: missing checkout")
        continue
    if name == "cofiswarm-infer-vllm" and not (path / "deploy/Dockerfile").is_file():
        bad.append(f"{name}: missing deploy/Dockerfile")
    rc = subprocess.run(["make", "test"], cwd=path, capture_output=True, text=True)
    if rc.returncode != 0:
        tail = (rc.stdout + rc.stderr).strip().splitlines()[-3:]
        bad.append(f"{name}: make test — {' | '.join(tail)}")
if bad:
    print("fail: phase 6 scaffold", file=sys.stderr)
    for b in bad:
        print(f"  {b}", file=sys.stderr)
    sys.exit(1)
names = ", ".join(r["name"].replace("cofiswarm-", "") for r in phase6)
print(f"ok: phase 6 scaffold ({len(phase6)} repos: {names})")
PY
