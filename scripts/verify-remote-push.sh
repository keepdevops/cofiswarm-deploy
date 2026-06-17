#!/usr/bin/env bash
# Sprint 58: read-only origin vs pin status (non-fatal; exits 0).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
TAG="${RELEASE_TAG:-v1.1.0}"
MONO_TAG="${MONOREPO_RELEASE_TAG:-v1.1.0-migration}"

python3 - "$ROOT/repos.json" "$REPOS" "$TAG" <<'PY'
import json, subprocess, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text())
repos_root = Path(sys.argv[2])
tag = sys.argv[3]
synced = drift = missing = 0
for name, pin in (doc.get("pins") or {}).items():
    if not pin:
        continue
    path = repos_root / name
    if not (path / ".git").is_dir():
        print(f"  ? {name}: no checkout")
        missing += 1
        continue
    branch = subprocess.check_output(
        ["git", "-C", str(path), "rev-parse", "--abbrev-ref", "HEAD"], text=True
    ).strip()
    r = subprocess.run(
        ["git", "-C", str(path), "ls-remote", "origin", f"refs/heads/{branch}"],
        capture_output=True, text=True,
    )
    remote = (r.stdout or "").strip().split()
    if len(remote) < 1 or remote[0] != pin:
        got = remote[0][:8] if remote else "missing"
        print(f"  ✗ {name}: origin/{branch} {got} != pin {pin[:8]}")
        drift += 1
        continue
    r2 = subprocess.run(
        ["git", "-C", str(path), "ls-remote", "--tags", "origin", f"refs/tags/{tag}"],
        capture_output=True, text=True,
    )
    if not (r2.stdout or "").strip():
        print(f"  ✗ {name}: origin missing tag {tag}")
        drift += 1
        continue
    synced += 1
print(f"synced: {synced}  drift: {drift}  missing checkout: {missing}")
if drift or missing:
    print("hint: ./scripts/push-all-repos.sh && REMOTE_REQUIRE=1 make remote-complete")
PY

r=$(git -C "$MONO" ls-remote --tags origin "refs/tags/${MONO_TAG}" 2>/dev/null | awk '{print $1}' | head -1)
if [[ -n "$r" ]]; then
  echo "ok: monorepo origin tag ${MONO_TAG} @${r:0:8}"
else
  echo "warn: monorepo origin missing ${MONO_TAG}"
fi
