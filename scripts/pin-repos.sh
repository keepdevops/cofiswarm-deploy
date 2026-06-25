#!/usr/bin/env bash
# Refresh repos.json pins from local ~/cofiswarm/repos checkouts.
# Optionally stamp a new release version: RELEASE_VERSION=1.2.1 make pin-repos
# (bare "1.2.1"; release becomes "v1.2.1"). When unset, the existing version is
# kept. Historical *_signoff markers are never clobbered here — they're managed
# by their own render-*-signoff targets.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"
python3 - "$ROOT/repos.json" "$REPOS" "${RELEASE_VERSION:-}" <<'PY'
import json, subprocess, sys
from pathlib import Path

repos_file, repos_root = Path(sys.argv[1]), Path(sys.argv[2])
new_version = sys.argv[3].strip().lstrip("v")  # "" = keep existing
doc = json.loads(repos_file.read_text())
archived = {"cofiswarm-coordinator", "cofiswarm-proxy", "cofiswarm-gateway",
            "cofiswarm-pgvector"}  # RAG is serverless (sqlite-vec) now
pins = {}
for r in doc["repos"]:
    name = r["name"]
    path = repos_root / name
    if not (path / ".git").is_dir():
        pins[name] = r.get("pin")
        continue
    sha = subprocess.check_output(
        ["git", "-C", str(path), "rev-parse", "HEAD"], text=True
    ).strip()
    pins[name] = sha
    r["pin"] = sha
    if name in archived:
        r["status"] = "archived"
        r["required"] = False
doc["pins"] = pins
if new_version:
    doc["version"] = new_version
    doc["release"] = f"v{new_version}"
repos_file.write_text(json.dumps(doc, indent=2) + "\n")
print(f"pinned {sum(1 for v in pins.values() if v)} repos → {doc['release']}")
PY
