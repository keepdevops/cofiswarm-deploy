#!/usr/bin/env bash
# Sprint 36: repos.json pins match local checkouts.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"

python3 - "$ROOT/repos.json" "$REPOS" <<'PY'
import json, subprocess, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text())
root = Path(sys.argv[2])
pins = doc.get("pins") or {}
bad = []
for name, pin in pins.items():
    if not pin:
        continue
    path = root / name
    if not (path / ".git").is_dir():
        continue
    head = subprocess.check_output(
        ["git", "-C", str(path), "rev-parse", "HEAD"], text=True
    ).strip()
    if head != pin:
        bad.append(f"{name}: pin {pin[:8]} != HEAD {head[:8]}")
for r in doc.get("repos", []):
    if r["name"] == "cofiswarm-gateway" and r.get("status") != "archived":
        bad.append("cofiswarm-gateway not archived in repos.json")
if bad:
    print("fail: pin drift", file=sys.stderr)
    for b in bad[:10]:
        print(f"  {b}", file=sys.stderr)
    sys.exit(1)
ver = doc.get("migration_signoff")
if not ver:
    print("fail: missing migration_signoff in repos.json", file=sys.stderr)
    sys.exit(1)
print(f"ok: repos pins ({len(pins)} entries, migration_signoff={ver})")
PY
