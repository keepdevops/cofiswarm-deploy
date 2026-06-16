#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"

grep -q delegateToDeploy "${MONO}/bin/matrix.mjs" || { echo "matrix.mjs not patched"; exit 1; }
[[ -f "${FHS}/var/lib/cofiswarm/dispatch/sessions/sessions.json" ]] || { echo "FHS sessions missing"; exit 1; }
[[ -f "${ROOT}/repos.json" ]] && python3 -c "import json; d=json.load(open('${ROOT}/repos.json')); assert d.get('version')=='1.0.0'; assert 'pins' in d"
for repo in cofiswarm-coordinator cofiswarm-proxy; do
  [[ -f "${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}/${repo}/ARCHIVED.md" ]]
done
python3 -c "import json; d=json.load(open('${ROOT}/repos.json')); assert d['repos'][[r['name'] for r in d['repos']].index('cofiswarm-coordinator')].get('status')=='archived'"
echo "ok: cutover gate"
