#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../standalone" && pwd)"
REPOS_JSON="$(cd "$(dirname "$0")/../.." && pwd)/repos.json"
python3 -c "
import json, pathlib, sys
repos = json.load(open('$REPOS_JSON'))['repos']
root = pathlib.Path('$ROOT')
missing = []
for r in repos:
    name = r['name'].replace('cofiswarm-', '')
    for sub in ['etc/cofiswarm', 'var/lib/cofiswarm', 'var/log/cofiswarm']:
        p = root / sub / name
        if name in ('common','stream-sdk','e2e','docs','grafana','models','backend-sdk','observer-sdk','mode-sdk','backend-llama','backend-mlx','backend-vllm','tools','rag-worker','convert','pgvector'):
            continue
        if not p.exists() and not (sub == 'etc/cofiswarm' and name == 'config'):
            missing.append(str(p))
if missing:
    print('missing:', *missing, sep='\n  ')
    sys.exit(1)
print('ok: full standalone layout', len(repos), 'repos')
"
