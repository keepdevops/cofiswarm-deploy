#!/usr/bin/env bash
# Sprint 54: Phase 7 optional repos — layout + static make test.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"

python3 - "$ROOT/repos.json" "$REPOS" <<'PY'
import json, subprocess, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text())
repos_root = Path(sys.argv[2])
phase7 = [r for r in doc.get("repos") or [] if r.get("phase") == 7]
if not phase7:
    raise SystemExit("fail: no phase-7 repos in repos.json")
bad = []
for r in phase7:
    name = r["name"]
    if r.get("required"):
        bad.append(f"{name}: phase 7 must be optional (required=false)")
    path = repos_root / name
    if not path.is_dir():
        bad.append(f"{name}: missing checkout")
        continue
    rc = subprocess.run(["make", "test"], cwd=path, capture_output=True, text=True)
    if rc.returncode != 0:
        tail = (rc.stdout + rc.stderr).strip().splitlines()[-3:]
        bad.append(f"{name}: make test — {' | '.join(tail)}")
if bad:
    print("fail: phase 7 scaffold", file=sys.stderr)
    for b in bad:
        print(f"  {b}", file=sys.stderr)
    sys.exit(1)
names = ", ".join(r["name"].replace("cofiswarm-", "") for r in phase7)
print(f"ok: phase 7 scaffold ({len(phase7)} repos: {names})")
PY
