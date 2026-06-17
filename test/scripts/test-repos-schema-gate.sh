#!/usr/bin/env bash
# Sprint 44: repos.json schema (CI-safe — no local pin drift).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

python3 - "$ROOT/repos.json" <<'PY'
import json, sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text())
repos = doc.get("repos") or []
pins = doc.get("pins") or {}
required = [r["name"] for r in repos if r.get("required")]
archived = {r["name"] for r in repos if r.get("status") == "archived"}
for key in (
    "release",
    "migration_signoff",
    "observability_signoff",
    "device_ops_signoff",
    "security_signoff",
    "ci_signoff",
    "sidecars_signoff",
    "repo_layout_signoff",
    "version",
):
    if not doc.get(key):
        raise SystemExit(f"fail: repos.json missing {key}")
if "cofiswarm-gateway" not in archived:
    raise SystemExit("fail: cofiswarm-gateway must be archived")
if len(pins) < 40:
    raise SystemExit(f"fail: expected >=40 pins, got {len(pins)}")
if len(required) < 25:
    raise SystemExit(f"fail: expected >=25 required repos, got {len(required)}")
print(f"ok: repos schema ({len(repos)} repos, {len(pins)} pins, release={doc['release']})")
PY
