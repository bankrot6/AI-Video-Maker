#!/usr/bin/env bash
# Shared infrastructure: one implementation for every application.
# Default: validate only. Pass --apply after reviewing the checks.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_ROOT="${SHARED_AI_INFRA_ROOT:-$SCRIPT_DIR/../../AIplate/server/shared-ai-infra}"
[[ -f "$SHARED_ROOT/deploy.py" ]] || { echo "Shared AI infrastructure missing: $SHARED_ROOT" >&2; exit 1; }
exec python3 "$SHARED_ROOT/deploy.py" relay "$@"
