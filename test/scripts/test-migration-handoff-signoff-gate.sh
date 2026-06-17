#!/usr/bin/env bash
# Sprint 59: operator handoff — remote-complete + consolidated verify.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"

"${ROOT}/test/scripts/test-remote-complete-signoff-gate.sh"
VERIFY_MIGRATION_STRICT=1 VERIFY_MIGRATION_SKIP_HANDOFF_DOC=1 "${ROOT}/scripts/verify-migration.sh"

for f in REMOTE-COMPLETE-SIGNOFF.md; do
  [[ -f "${MONO}/docs/${f}" ]] || { echo "fail: missing ${MONO}/docs/${f}" >&2; exit 1; }
  echo "ok: ${f}"
done

python3 - "$ROOT/repos.json" <<'PY'
import json, sys
from pathlib import Path
doc = json.loads(Path(sys.argv[1]).read_text())
if not doc.get("migration_handoff_signoff"):
    raise SystemExit("fail: repos.json missing migration_handoff_signoff")
print(f"ok: migration_handoff_signoff={doc['migration_handoff_signoff']}")
PY

echo "ok: migration handoff signoff"
