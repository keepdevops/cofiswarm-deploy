#!/usr/bin/env bash
# Sprint 56: origin refs match repos.json pins + v1.1.0 tags (optional REMOTE_REQUIRE=1).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
TAG="${RELEASE_TAG:-v1.1.0}"
MONO_TAG="${MONOREPO_RELEASE_TAG:-v1.1.0-migration}"

if [[ "${REMOTE_REQUIRE:-}" != "1" ]]; then
  echo "ok: remote sync skip (set REMOTE_REQUIRE=1 after ./scripts/push-all-repos.sh)"
  exit 0
fi

python3 - "$ROOT/repos.json" "$REPOS" "$TAG" <<'PY'
import json, subprocess, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text())
repos_root = Path(sys.argv[2])
tag = sys.argv[3]
bad = []
ok = 0
for name, pin in (doc.get("pins") or {}).items():
    if not pin:
        continue
    path = repos_root / name
    if not (path / ".git").is_dir():
        bad.append(f"{name}: missing checkout")
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
        bad.append(f"{name}: origin/{branch} {got} != pin {pin[:8]}")
        continue
    r2 = subprocess.run(
        ["git", "-C", str(path), "ls-remote", "--tags", "origin", f"refs/tags/{tag}"],
        capture_output=True,
        text=True,
    )
    line = (r2.stdout or "").strip().splitlines()
    if not line:
        bad.append(f"{name}: origin missing tag {tag}")
        continue
    local = subprocess.check_output(
        ["git", "-C", str(path), "rev-parse", tag], text=True
    ).strip()
    if line[0].split()[0] != local:
        bad.append(f"{name}: origin {tag} drift")
        continue
    ok += 1
if bad:
    print("fail: remote sync", file=sys.stderr)
    for b in bad[:12]:
        print(f"  {b}", file=sys.stderr)
    if len(bad) > 12:
        print(f"  … +{len(bad) - 12} more", file=sys.stderr)
    sys.exit(1)
print(f"ok: remote sync ({ok} repos on origin @ {tag})")
PY

r=$(git -C "$MONO" ls-remote --tags origin "refs/tags/${MONO_TAG}" 2>/dev/null | awk '{print $1}' | head -1)
[[ -n "$r" ]] || { echo "fail: cofiswarmdev origin missing ${MONO_TAG}" >&2; exit 1; }
echo "ok: monorepo remote tag ${MONO_TAG}"
