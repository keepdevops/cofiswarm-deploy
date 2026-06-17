#!/usr/bin/env bash
# Sprint 41 legacy wrapper — use tag-all-repos.sh for full 43-repo cut.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "${ROOT}/scripts/tag-all-repos.sh"
