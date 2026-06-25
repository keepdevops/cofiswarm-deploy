#!/usr/bin/env bash
# Write ${COFISWARM_REPOS_ROOT}/go.work for sibling Go modules (no ../ replace).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"
OUT="${REPOS}/go.work"

python3 - "$ROOT/repos.json" "$OUT" "$REPOS" <<'PY'
import json, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text())
out = Path(sys.argv[2])
repos = Path(sys.argv[3])
go_mods = []
sdk = "cofiswarm-mode-sdk"
for r in doc.get("repos") or []:
    name = r["name"]
    path = repos / name
    if (path / "go.mod").is_file() and name != sdk:
        go_mods.append(name)
lines = ["go 1.25.0", ""]
for name in sorted(go_mods):
    lines.append(f"use ./{name}")
lines.append("")
lines.append(f"replace github.com/keepdevops/{sdk} => ./{sdk}")
lines.append("")
out.write_text("\n".join(lines))
print(f"rendered {out} ({len(go_mods)} modules)")
PY
