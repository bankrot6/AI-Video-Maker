#!/usr/bin/env bash
set -euo pipefail

# Auto-setup Yandex Search API v2 (works with XML endpoint too)
# - Creates service account (if missing)
# - Grants role search-api.webSearch.user on the folder
# - Creates API key (prints and writes to .env)
# Requirements: curl, python3

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

echo "==> Yandex Search API auto-setup"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env file not found at $ENV_FILE"
  exit 1
fi

source "$ENV_FILE" || true

FOLDER_ID="${YANDEX_FOLDER_ID:-}"
OAUTH_TOKEN="${YANDEX_OAUTH_TOKEN:-}"
SERVICE_ACCOUNT_ID="${YANDEX_SERVICE_ACCOUNT_ID:-}"

if [[ -z "$OAUTH_TOKEN" ]]; then
  echo "ERROR: YANDEX_OAUTH_TOKEN is not set in .env"
  exit 1
fi

echo "-> Getting IAM token via OAuth..."
IAM_TOKEN=$(curl -sS -X POST \
  -H 'Content-Type: application/json' \
  -d "{\"yandexPassportOauthToken\":\"$OAUTH_TOKEN\"}" \
  https://iam.api.cloud.yandex.net/iam/v1/tokens \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("iamToken",""))')

if [[ -z "$IAM_TOKEN" ]]; then
  echo "ERROR: Failed to obtain IAM token. Check YANDEX_OAUTH_TOKEN."
  exit 1
fi
echo "OK: IAM token acquired"

ensure_folder() {
  # If FOLDER_ID provided, verify it exists
  if [[ -n "${FOLDER_ID:-}" ]]; then
    F_GET=$(curl -sS -H "Authorization: Bearer $IAM_TOKEN" \
      "https://resource-manager.api.cloud.yandex.net/resource-manager/v1/folders/$FOLDER_ID")
    F_OK=$(python3 -c 'import sys,json; d=json.load(sys.stdin); print("1" if d.get("id") else "")' <<< "$F_GET") || true
    if [[ -n "$F_OK" ]]; then
      echo "OK: Using existing folder: $FOLDER_ID"
      return
    else
      echo "-> Provided FOLDER_ID not found. Will try to auto-detect."
    fi
  fi

  echo "-> Listing clouds..."
  CLOUDS_JSON=$(curl -sS -H "Authorization: Bearer $IAM_TOKEN" \
    "https://resource-manager.api.cloud.yandex.net/resource-manager/v1/clouds")
  CLOUD_ID=$(python3 - <<'PY'
import sys, json
d=json.load(sys.stdin)
items=d.get('clouds',[])
print(items[0]['id'] if items else '')
PY
<<< "$CLOUDS_JSON")
  if [[ -z "$CLOUD_ID" ]]; then
    echo "ERROR: No clouds accessible for this account/token"
    exit 1
  fi
  echo "OK: Cloud detected: $CLOUD_ID"

  echo "-> Listing folders in cloud..."
  FOLDERS_JSON=$(curl -sS -H "Authorization: Bearer $IAM_TOKEN" \
    "https://resource-manager.api.cloud.yandex.net/resource-manager/v1/folders?cloudId=$CLOUD_ID")
  # Try to pick 'default' folder
  FOLDER_ID=$(python3 - <<'PY'
import sys, json
d=json.load(sys.stdin)
items=d.get('folders',[])
cid=''
for f in items:
    if f.get('name')=='default':
        cid=f.get('id'); break
print(cid or (items[0]['id'] if items else ''))
PY
<<< "$FOLDERS_JSON")
  if [[ -z "$FOLDER_ID" ]]; then
    echo "ERROR: No folders found in cloud. Create a folder in console first."
    exit 1
  fi
  echo "OK: Folder selected: $FOLDER_ID"

  # Update .env with detected folder
  if grep -q "^YANDEX_FOLDER_ID=" "$ENV_FILE"; then
    sed -i '' -E "s#^YANDEX_FOLDER_ID=.*#YANDEX_FOLDER_ID=$FOLDER_ID#" "$ENV_FILE"
  else
    echo "YANDEX_FOLDER_ID=$FOLDER_ID" >> "$ENV_FILE"
  fi
}

ensure_service_account() {
  if [[ -n "${SERVICE_ACCOUNT_ID:-}" ]]; then
    echo "-> Checking existing service account: $SERVICE_ACCOUNT_ID"
    SA_GET=$(curl -sS -H "Authorization: Bearer $IAM_TOKEN" \
      "https://iam.api.cloud.yandex.net/iam/v1/serviceAccounts/$SERVICE_ACCOUNT_ID")
    SA_NAME_PRESENT=$(python3 -c 'import sys,json; d=json.load(sys.stdin); print("1" if d.get("id") else "")' <<< "$SA_GET") || true
    if [[ -z "$SA_NAME_PRESENT" ]]; then
      echo "-> Existing SA id not found. Will create a new service account."
      SERVICE_ACCOUNT_ID=""
    else
      echo "OK: Service account exists"
    fi
  fi

  if [[ -z "${SERVICE_ACCOUNT_ID}" ]]; then
    echo "-> Creating service account in folder $FOLDER_ID"
    SA_NAME="chatcoach-search-$(date +%s)"
    SA_JSON=$(curl -sS -X POST \
      -H "Authorization: Bearer $IAM_TOKEN" \
      -H 'Content-Type: application/json' \
      -d "{\"folderId\":\"$FOLDER_ID\",\"name\":\"$SA_NAME\",\"description\":\"ChatCoach Search API auto\"}" \
      https://iam.api.cloud.yandex.net/iam/v1/serviceAccounts)
    SERVICE_ACCOUNT_ID=$(python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))' <<< "$SA_JSON")
    if [[ -z "$SERVICE_ACCOUNT_ID" ]]; then
      echo "ERROR: Failed to create service account: $SA_JSON"
      exit 1
    fi
    echo "OK: Service account created: $SERVICE_ACCOUNT_ID"
  fi
}

ensure_folder
ensure_service_account

echo "-> Granting role search-api.webSearch.user on folder $FOLDER_ID to SA $SERVICE_ACCOUNT_ID"
AB_PAYLOAD=$(cat <<JSON
{
  "accessBindingDeltas": [
    {
      "action": "ADD",
      "accessBinding": {
        "roleId": "search-api.webSearch.user",
        "subject": { "id": "$SERVICE_ACCOUNT_ID", "type": "serviceAccount" }
      }
    }
  ]
}
JSON
)

AB_RESP=$(curl -sS -X POST \
  -H "Authorization: Bearer $IAM_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "$AB_PAYLOAD" \
  "https://resource-manager.api.cloud.yandex.net/resource-manager/v1/folders/$FOLDER_ID:updateAccessBindings")
echo "OK: Role grant requested"

echo "-> Creating Search API key for SA"
API_KEY_JSON=$(curl -sS -X POST \
  -H "Authorization: Bearer $IAM_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"serviceAccountId\":\"$SERVICE_ACCOUNT_ID\",\"description\":\"API key for ChatCoach Search API (auto)\"}" \
  https://iam.api.cloud.yandex.net/iam/v1/apiKeys)

API_KEY_SECRET=$(python3 -c 'import sys,json; print(json.load(sys.stdin).get("secret",""))' <<< "$API_KEY_JSON")
if [[ -z "$API_KEY_SECRET" ]]; then
  echo "ERROR: Failed to create API key: $API_KEY_JSON"
  exit 1
fi
echo "OK: API key created"

echo "-> Updating .env with SA and API key"
update_env() {
  local key="$1" val="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i '' -E "s#^${key}=.*#${key}=${val//#/\\#}#" "$ENV_FILE"
  else
    echo "${key}=${val}" >> "$ENV_FILE"
  fi
}

update_env YANDEX_SERVICE_ACCOUNT_ID "$SERVICE_ACCOUNT_ID"
update_env YANDEX_SEARCH_API_KEY "$API_KEY_SECRET"

echo "-> Verifying XML endpoint access (trial request)"
VERIFY=$(curl -sS -H "Authorization: Api-Key $API_KEY_SECRET" \
  "https://yandex.ru/search/xml?folderid=$FOLDER_ID&query=vkvideo&lr=213&l10n=ru&sortby=rlv" | head -c 300)
echo "$VERIFY"

echo "\n==> Done. .env updated with YANDEX_SERVICE_ACCOUNT_ID and YANDEX_SEARCH_API_KEY"


