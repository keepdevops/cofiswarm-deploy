#!/usr/bin/env bash
# Refresh repos.json pins from local ~/cofiswarm/repos checkouts.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"
python3 - "$ROOT/repos.json" "$REPOS" <<'PY'
import json, subprocess, sys
from pathlib import Path

repos_file, repos_root = Path(sys.argv[1]), Path(sys.argv[2])
doc = json.loads(repos_file.read_text())
archived = {"cofiswarm-coordinator", "cofiswarm-proxy", "cofiswarm-gateway"}
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
doc["version"] = "1.1.0"
doc["release"] = "v1.1.0"
doc["migration_signoff"] = "v1.1.0"
doc["observability_signoff"] = "v1.1.0"
doc["device_ops_signoff"] = "v1.1.0"
doc["security_signoff"] = "v1.1.0"
doc["ci_signoff"] = "v1.1.0"
doc["sidecars_signoff"] = "v1.1.0"
doc["repo_layout_signoff"] = "v1.1.0"
doc["go_modules_signoff"] = "v1.1.0"
doc["repo_ci_signoff"] = "v1.1.0"
doc["go_ci_signoff"] = "v1.1.0"
doc["mode_sdk_release_signoff"] = "v1.1.0"
repos_file.write_text(json.dumps(doc, indent=2) + "\n")
print(f"pinned {sum(1 for v in pins.values() if v)} repos → {doc['release']} (post-migration signoffs v1.1.0)")
PY
