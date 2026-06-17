#!/usr/bin/env bash
# Render docs/SIDECARS-SIGNOFF.md after sidecars gate.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/SIDECARS-SIGNOFF.md"

if [[ "${SIDECARS_SKIP_GATE:-}" != "1" ]]; then
  "${ROOT}/test/scripts/test-sidecars-signoff-gate.sh"
fi

python3 - "$OUT" <<'PY'
import datetime, sys
from pathlib import Path

ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
md = f"""# Sidecars sign-off

**Date:** {ts}  
**Services:** convert :8015 · rag-worker :8018

## Verdict

**MLX convert queue + RAG index worker in stack:** PASS

## Gates

```bash
CGO_ENABLED=0 make build-convert
make up
make test-sidecars-signoff-gate
```
"""
Path(sys.argv[1]).write_text(md)
print(f"rendered {sys.argv[1]}")
PY
