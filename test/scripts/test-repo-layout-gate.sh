#!/usr/bin/env bash
# Sprint 47: every pinned repo — standalone FHS layout, no git submodules.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"

python3 - "$ROOT/repos.json" "$REPOS" <<'PY'
import json, os, subprocess, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text())
repos_root = Path(sys.argv[2])
bad = []
for r in doc.get("repos") or []:
    name = r["name"]
    role = name.replace("cofiswarm-", "")
    path = repos_root / name
    if not path.is_dir():
        bad.append(f"{name}: missing checkout")
        continue
    for rel in ("README.md", "Makefile", "test/scripts/assert-layout.sh", "test/standalone"):
        if not (path / rel).exists():
            bad.append(f"{name}: missing {rel}")
    if (path / ".gitmodules").exists():
        bad.append(f"{name}: has .gitmodules (no child repos)")
    script = path / "test/scripts/assert-layout.sh"
    if script.exists():
        rc = subprocess.run(
            [str(script), role],
            cwd=path,
            capture_output=True,
            text=True,
        )
        if rc.returncode != 0:
            bad.append(f"{name}: assert-layout — {rc.stdout}{rc.stderr}".strip())
if bad:
    print("fail: repo layout", file=sys.stderr)
    for b in bad[:20]:
        print(f"  {b}", file=sys.stderr)
    sys.exit(1)
print(f"ok: repo layout ({len(doc.get('repos') or [])} repos, standalone FHS, no submodules)")
PY
