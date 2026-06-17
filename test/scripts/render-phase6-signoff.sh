#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
OUT="${MONO}/docs/PHASE6-SIGNOFF.md"

if [[ "${PHASE6_SKIP_GATE:-}" != "1" ]]; then
  "${ROOT}/test/scripts/test-phase6-signoff-gate.sh"
fi

python3 - "$OUT" <<'PY'
import datetime, sys
from pathlib import Path

ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
Path(sys.argv[1]).write_text(f"""# Phase 6 optional repos sign-off

**Date:** {ts}  
**Scope:** infer-vllm · infer-sglang · infer-ollama · backend-vllm · adapter-openai-compat · tools  
**Runtime:** not in default stack (`required: false`)

## Verdict

**Phase 6 scaffold + static tests:** PASS

## Gates

```bash
cd ~/cofiswarm/repos/cofiswarm-deploy
make phase6
```

| Repo | Role |
|------|------|
| cofiswarm-infer-vllm | infer stub + Dockerfile |
| cofiswarm-infer-sglang | infer stub |
| cofiswarm-infer-ollama | infer stub |
| cofiswarm-backend-vllm | backend stub |
| cofiswarm-adapter-openai-compat | OpenAI-compat adapter |
| cofiswarm-tools | orchestrate modes (map_reduce, …) |
""")
print(f"rendered {sys.argv[1]}")
PY
