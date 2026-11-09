#!/usr/bin/env bash
set -euo pipefail
# Server compatibility entry point, backed by the same versioned release.
if [[ -f /opt/shared-ai-infra/current/manage.py ]]; then
  exec python3 /opt/shared-ai-infra/current/manage.py nginx "$@"
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/../deploy_nginx_ai_proxy.sh" "$@"
