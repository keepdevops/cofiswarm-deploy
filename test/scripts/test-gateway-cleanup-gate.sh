#!/usr/bin/env bash
# Sprint 34: static audit — no :3002 in active nginx configs; dispatch :8010 canonical.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"
PORTS="${REPOS}/cofiswarm-common/ports/well-known.yaml"

fail() { echo "fail: $*" >&2; exit 1; }

grep -q 'dispatch: 8010' "$PORTS" || fail "well-known.yaml missing dispatch:8010"
grep -q 'gateway_legacy_proxy: 3002' "$PORTS" || fail "well-known.yaml missing gateway_legacy_proxy"

for f in \
  "${ROOT}/config/gateway/nginx.conf" \
  "${REPOS}/cofiswarm-ui/deploy/nginx.conf"; do
  [[ -f "$f" ]] || fail "missing $f"
  grep -q 'host.docker.internal:8010' "$f" || fail "$f does not proxy to dispatch :8010"
  grep -q ':3002' "$f" && fail "$f still references :3002"
done

grep -q 'host.docker.internal:8010' "${REPOS}/cofiswarm-gateway/deploy/nginx.conf" \
  || fail "gateway nginx not retargeted to dispatch"
grep -q 'DEPRECATED' "${REPOS}/cofiswarm-gateway/docs/DEPRECATED.md" \
  || fail "gateway DEPRECATED.md missing"

echo "ok: gateway cleanup — dispatch :8010 canonical, :3002 legacy only in well-known"
