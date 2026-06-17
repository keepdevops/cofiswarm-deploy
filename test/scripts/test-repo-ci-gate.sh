#!/usr/bin/env bash
# Sprint 49: every repo has .github/workflows/ci.yml (GitHub Actions standards).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"

python3 - "$ROOT/repos.json" "$REPOS" <<'PY'
import json, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text())
repos_root = Path(sys.argv[2])
bad = []
for r in doc.get("repos") or []:
    name = r["name"]
    ci = repos_root / name / ".github/workflows/ci.yml"
    if not ci.is_file():
        bad.append(f"{name}: missing .github/workflows/ci.yml")
        continue
    text = ci.read_text()
    if "actions/checkout@v6" not in text:
        bad.append(f"{name}: ci.yml missing checkout@v6")
    if name == "cofiswarm-deploy":
        if "test-ci-static-gate" not in text:
            bad.append(f"{name}: deploy ci must run test-ci-static-gate")
    elif name == "cofiswarm-ui":
        if "npm test" not in text:
            bad.append(f"{name}: ui ci must run npm test")
    elif "make test" not in text:
        bad.append(f"{name}: ci.yml missing make test")
if bad:
    print("fail: repo ci", file=sys.stderr)
    for b in bad:
        print(f"  {b}", file=sys.stderr)
    sys.exit(1)
print(f"ok: repo ci ({len(doc.get('repos') or [])} workflows)")
PY
