#!/usr/bin/env bash
# Sprint 55: every pinned repo has RELEASE_TAG at repos.json pin SHA.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
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
pins = doc.get("pins") or {}
bad = []
ok = 0
for name, pin in pins.items():
    if not pin:
        continue
    path = repos_root / name
    if not (path / ".git").is_dir():
        bad.append(f"{name}: missing checkout")
        continue
    r = subprocess.run(
        ["git", "-C", str(path), "rev-parse", f"{tag}^{{commit}}"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        bad.append(f"{name}: missing tag {tag} (run ./scripts/tag-all-repos.sh)")
        continue
    if r.stdout.strip() != pin:
        bad.append(f"{name}: {tag} @{r.stdout.strip()[:8]} != pin {pin[:8]}")
        continue
    ok += 1
if bad:
    print("fail: all-release-tags", file=sys.stderr)
    for b in bad[:12]:
        print(f"  {b}", file=sys.stderr)
    if len(bad) > 12:
        print(f"  … +{len(bad) - 12} more", file=sys.stderr)
    sys.exit(1)
print(f"ok: all-release-tags ({ok} repos @ {tag})")
PY

git -C "$MONO" rev-parse "${MONO_TAG}" >/dev/null 2>&1 || {
  echo "fail: cofiswarmdev missing tag ${MONO_TAG}" >&2
  exit 1
}
echo "ok: monorepo tag ${MONO_TAG}"

if [[ "${RELEASE_REQUIRE_REMOTE:-}" == "1" ]]; then
  python3 - "$ROOT/repos.json" "$REPOS" "$TAG" <<'PY'
import json, subprocess, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text())
repos_root = Path(sys.argv[2])
tag = sys.argv[3]
bad = []
for name, pin in (doc.get("pins") or {}).items():
    if not pin or not (repos_root / name / ".git").is_dir():
        continue
    r = subprocess.run(
        ["git", "-C", str(repos_root / name), "ls-remote", "--tags", "origin", f"refs/tags/{tag}"],
        capture_output=True, text=True,
    )
    line = (r.stdout or "").strip().splitlines()
    if not line:
        bad.append(f"{name}: origin missing {tag}")
        continue
    remote = line[0].split()[0]
    local = subprocess.check_output(
        ["git", "-C", str(repos_root / name), "rev-parse", tag], text=True
    ).strip()
    if remote != local:
        bad.append(f"{name}: origin {tag} drift")
if bad:
    print("fail: remote release tags", file=sys.stderr)
    for b in bad[:10]:
        print(f"  {b}", file=sys.stderr)
    sys.exit(1)
print(f"ok: remote release tags ({tag})")
PY
fi
