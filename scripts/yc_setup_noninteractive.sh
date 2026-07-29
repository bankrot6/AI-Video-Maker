#!/usr/bin/env bash
set -euo pipefail

# Non-interactive YC CLI setup for Yandex Search API
# - Installs yc CLI if missing
# - Configures profile with OAuth token
# - Detects/creates service account and API key
# - Grants role and updates .env

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env file not found at $ENV_FILE"
  exit 1
fi
source "$ENV_FILE" || true

OAUTH_TOKEN=${YANDEX_OAUTH_TOKEN:-}
FOLDER_ID=${YANDEX_FOLDER_ID:-}
SERVICE_ACCOUNT_ID=${YANDEX_SERVICE_ACCOUNT_ID:-}

if [[ -z "$OAUTH_TOKEN" ]]; then
  echo "ERROR: YANDEX_OAUTH_TOKEN missing in .env"
  exit 1
fi

if ! command -v yc >/dev/null 2>&1; then
  echo "-> Installing YC CLI..."
  curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash
  export PATH="$HOME/yandex-cloud/bin:$PATH"
fi

export PATH="$HOME/yandex-cloud/bin:$PATH"

echo "-> Configure YC env (no interactive)"
export YC_TOKEN="$OAUTH_TOKEN"

echo "-> Detect cloud"
CLOUD_ID=$(yc resource-manager cloud list --format json | python3 -c 'import sys,json; d=json.load(sys.stdin); print((d[0]["id"]) if isinstance(d,list) and d else (d.get("clouds",[{}])[0].get("id","")))')
if [[ -z "$CLOUD_ID" ]]; then
  echo "ERROR: Unable to detect cloud id"
  exit 1
fi
export YC_CLOUD_ID="$CLOUD_ID"

if [[ -z "$FOLDER_ID" ]]; then
  echo "-> Detect folder"
  FOLDER_ID=$(yc resource-manager folder list --cloud-id "$CLOUD_ID" --format json | python3 -c 'import sys,json; d=json.load(sys.stdin); print((d[0]["id"]) if isinstance(d,list) and d else (d.get("folders",[{}])[0].get("id","")))')
  if [[ -z "$FOLDER_ID" ]]; then
    echo "ERROR: No folders available in cloud. Create one in console."
    exit 1
  fi
  sed -i '' -E "s#^YANDEX_FOLDER_ID=.*#YANDEX_FOLDER_ID=$FOLDER_ID#" "$ENV_FILE" || echo "YANDEX_FOLDER_ID=$FOLDER_ID" >> "$ENV_FILE"
fi

export YC_FOLDER_ID="$FOLDER_ID"

echo "-> Ensure service account"
if [[ -n "$SERVICE_ACCOUNT_ID" ]]; then
  if ! yc iam service-account get --id "$SERVICE_ACCOUNT_ID" >/dev/null 2>&1; then
    SERVICE_ACCOUNT_ID=""
  fi
fi
if [[ -z "$SERVICE_ACCOUNT_ID" ]]; then
  SA_NAME="chatcoach-search-$(date +%s)"
  SERVICE_ACCOUNT_ID=$(yc iam service-account create --name "$SA_NAME" --folder-id "$FOLDER_ID" --format json | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("id",""))')
  if [[ -z "$SERVICE_ACCOUNT_ID" ]]; then
    echo "ERROR: Failed to create service account"
    exit 1
  fi
  sed -i '' -E "s#^YANDEX_SERVICE_ACCOUNT_ID=.*#YANDEX_SERVICE_ACCOUNT_ID=$SERVICE_ACCOUNT_ID#" "$ENV_FILE" || echo "YANDEX_SERVICE_ACCOUNT_ID=$SERVICE_ACCOUNT_ID" >> "$ENV_FILE"
fi

echo "-> Grant role search-api.webSearch.user"
yc resource-manager folder add-access-binding "$FOLDER_ID" --role search-api.webSearch.user --subject serviceAccount:"$SERVICE_ACCOUNT_ID" || true

echo "-> Create API key"
API_KEY_SECRET=$(yc iam api-key create --service-account-id "$SERVICE_ACCOUNT_ID" --description "ChatCoach Search API" --format json | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("secret",""))')
if [[ -z "$API_KEY_SECRET" ]]; then
  echo "ERROR: Failed to create API key (maybe already exists). Create manually and put to .env as YANDEX_SEARCH_API_KEY."
  exit 1
fi
sed -i '' -E "s#^YANDEX_SEARCH_API_KEY=.*#YANDEX_SEARCH_API_KEY=$API_KEY_SECRET#" "$ENV_FILE" || echo "YANDEX_SEARCH_API_KEY=$API_KEY_SECRET" >> "$ENV_FILE"

echo "Done. Updated .env with folder, SA and API key."

