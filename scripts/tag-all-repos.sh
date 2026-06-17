#!/usr/bin/env bash
# Annotated v1.1.0 tags on every pinned cofiswarm-* repo (at repos.json pin SHA).
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
tagged = 0
skipped = 0
for name, pin in (doc.get("pins") or {}).items():
    if not pin:
        continue
    path = repos_root / name
    if not (path / ".git").is_dir():
        print(f"skip: {name} (no checkout)")
        skipped += 1
        continue
    head = subprocess.check_output(
        ["git", "-C", str(path), "rev-parse", "HEAD"], text=True
    ).strip()
    if head != pin:
        print(f"warn: {name} HEAD {head[:8]} != pin {pin[:8]} (tagging pin)", file=sys.stderr)
    cur = subprocess.run(
        ["git", "-C", str(path), "rev-parse", f"{tag}^{{commit}}"],
        capture_output=True, text=True,
    )
    if cur.returncode == 0 and cur.stdout.strip() == pin:
        print(f"skip: {name} {tag} (already @{pin[:8]})")
        skipped += 1
        continue
    r = subprocess.run(
        ["git", "-C", str(path), "tag", "-fa", tag, pin, "-m", f"Cofiswarm {tag} device release."],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        print(f"fail: {name} tag — {r.stderr}", file=sys.stderr)
        sys.exit(1)
    print(f"tagged: {name} {tag} @{pin[:8]}")
    tagged += 1
print(f"ok: tag-all-repos ({tagged} tagged, {skipped} skipped)")
PY

git -C "$MONO" rev-parse "${MONO_TAG}^{commit}" >/dev/null 2>&1 \
  || git -C "$MONO" tag -a "${MONO_TAG}" -m "Cofiswarm monorepo ${TAG} migration sign-off."
echo "ok: monorepo tag ${MONO_TAG}"

echo "ok: release tags (push: git -C <repo> push origin ${TAG}; mono ${MONO_TAG})"
