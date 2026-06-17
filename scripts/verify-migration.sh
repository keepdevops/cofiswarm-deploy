#!/usr/bin/env bash
# Sprint 59: consolidated migration status (non-fatal; VERIFY_MIGRATION_STRICT=1 to fail).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"
STRICT="${VERIFY_MIGRATION_STRICT:-}"

fail=0
note() { echo "$*"; }
warn() { echo "warn: $*" >&2; fail=1; }
die()  { echo "fail: $*" >&2; exit 1; }

echo "==> local pin drift"
if ! "${ROOT}/test/scripts/test-repos-pins-gate.sh" 2>/dev/null; then
  if [[ -n "$STRICT" ]]; then die "local pin drift"; fi
  warn "local pin drift — run ./scripts/pin-repos.sh"
else
  note "ok: local pins match checkouts"
fi

echo "==> repos.json schema"
if ! "${ROOT}/test/scripts/test-repos-schema-gate.sh" 2>/dev/null; then
  [[ -n "$STRICT" ]] && die "repos.json schema"
  warn "repos.json schema"
else
  note "ok: repos.json schema"
fi

echo "==> signoff docs"
SIGNOFFS=(
  MIGRATION-SIGNOFF.md
  POST-MIGRATION-SIGNOFF.md
  MIGRATION-COMPLETE-SIGNOFF.md
  REMOTE-COMPLETE-SIGNOFF.md
  MIGRATION-HANDOFF.md
)
missing=0
for f in "${SIGNOFFS[@]}"; do
  if [[ -f "${MONO}/docs/${f}" ]]; then
    note "  ok: ${f}"
  else
    if [[ "$f" == "MIGRATION-HANDOFF.md" && -n "${VERIFY_MIGRATION_SKIP_HANDOFF_DOC:-}" ]]; then
      note "  skip: ${f} (pre-render)"
      continue
    fi
    missing=$((missing + 1))
    if [[ -n "$STRICT" ]]; then
      die "missing ${MONO}/docs/${f}"
    fi
    warn "missing ${f}"
  fi
done
[[ "$missing" -eq 0 ]] && note "ok: handoff signoff docs (${#SIGNOFFS[@]})"

echo "==> remote origin sync"
"${ROOT}/scripts/verify-remote-push.sh" || true

if [[ -n "$STRICT" && "$fail" -ne 0 ]]; then
  die "verify-migration strict checks failed"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "hint: ./scripts/pin-repos.sh && make migration-handoff"
else
  echo "ok: verify-migration"
fi
