#!/usr/bin/env bash
# Deploy a single Appwrite Function.
#
# Usage:
#   bash scripts/deploy_single_appwrite_function.sh verify-trial
#   bash scripts/deploy_single_appwrite_function.sh apibost-proxy

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FUNC_ID="${1:-}"

if [[ -z "$FUNC_ID" ]]; then
  echo "Usage: bash scripts/deploy_single_appwrite_function.sh <function-id>"
  echo ""
  echo "Available:"
  echo "  verify-trial"
  echo "  apibost-proxy"
  echo "  verify-rustore-purchase"
  echo "  generate-thumbnail"
  echo "  process-preset-rewards"
  echo "  repair-preset-permissions"
  echo "  daily-preset-pipeline"
  echo "  manage-presets"
  echo "  ad-creative-generator"
  exit 1
fi

ENV_FILE="$PROJECT_ROOT/.env"
DEPLOY_SECRETS_FILE="${DEPLOY_SECRETS_FILE:-$PROJECT_ROOT/.env.deploy}"
FUNCTIONS_DIR="$PROJECT_ROOT/appwrite-functions"

[[ ! -f "$ENV_FILE" ]] && {
  echo "ERROR: .env not found at $ENV_FILE"
  exit 1
}

get_env() {
  local key="$1" default="${2:-}"
  local val
  if [[ -f "$DEPLOY_SECRETS_FILE" ]]; then
    val=$(grep -E "^${key}[[:space:]]*=" "$DEPLOY_SECRETS_FILE" 2>/dev/null | head -1 | cut -d'=' -f2-)
    val="${val%\"}" ; val="${val#\"}" ; val="${val%\'}" ; val="${val#\'}"
  fi
  if [[ -z "$val" ]]; then
    val=$(grep -E "^${key}[[:space:]]*=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d'=' -f2-)
    val="${val%\"}" ; val="${val#\"}" ; val="${val%\'}" ; val="${val#\'}"
  fi
  printf '%s' "${val:-$default}"
}

ENDPOINT=$(get_env    "APPWRITE_ENDPOINT")
PROJECT_ID=$(get_env  "APPWRITE_PROJECT_ID")
API_KEY=$(get_env     "APPWRITE_API_KEY")
DATABASE_ID=$(get_env "APPWRITE_DATABASE_ID"           "main")
PRESETS_COLL=$(get_env "APPWRITE_PRESETS_COLLECTION_ID" "presets")
BUCKET_ID=$(get_env   "APPWRITE_STORAGE_BUCKET_ID"     "user-photos")
DEEPSEEK_KEY=$(get_env "DEEPSEEK_API_KEY")
API_BOST_KEY=$(get_env "API_BOST_API_KEY")
ADMIN_KEY=$(get_env   "ADMIN_API_KEY" "photosession_admin_key_2026_secure_secret")
DAILY_PRESET_PIPELINE_CRON_ENABLED=$(get_env "DAILY_PRESET_PIPELINE_CRON_ENABLED" "false")
NL_SERVER_HOST=$(get_env "NL_SERVER_HOST")
NL_PROXY_TOKEN=$(get_env "NL_PROXY_TOKEN")
AI_PROXY_PIAPI_PORT=$(get_env "AI_PROXY_PIAPI_PORT" "8080")
AI_PROXY_DEEPSEEK_PORT=$(get_env "AI_PROXY_DEEPSEEK_PORT" "8001")
YANDEX_AI_RELAY_BASE_URL=$(get_env "YANDEX_AI_RELAY_BASE_URL")
APPWRITE_AD_CREATIVES_BUCKET_ID=$(get_env "APPWRITE_AD_CREATIVES_BUCKET_ID" "ad-creatives")
RUSTORE_APP_ID=$(get_env "RUSTORE_APP_ID" "2063737207")
RUSTORE_KEY_ID=$(get_env "RUSTORE_KEY_ID")
RUSTORE_PRIVATE_KEY=$(get_env "RUSTORE_PRIVATE_KEY")
MYTRACKER_S2S_TOKEN=$(get_env "MYTRACKER_S2S_TOKEN")
MYTRACKER_S2S_APP_ID=$(get_env "MYTRACKER_S2S_APP_ID" "1055317")

[[ -z "$ENDPOINT" || -z "$PROJECT_ID" || -z "$API_KEY" ]] && {
  echo "ERROR: APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY must be set in .env"
  exit 1
}

detect_node_runtime() {
  local runtimes_json
  for attempt in 1 2 3; do
    runtimes_json=$(curl -s --max-time 15 \
      -H "X-Appwrite-Project: $PROJECT_ID" \
      -H "X-Appwrite-Key: $API_KEY" \
      "$ENDPOINT/functions/runtimes" 2>/dev/null || true)
    for candidate in node-20.0 node-18.0 node-16.0; do
      if echo "$runtimes_json" | grep -q "\"$candidate\""; then
        echo "$candidate"
        return
      fi
    done
    [[ $attempt -lt 3 ]] && sleep 10
  done
  echo "node-18.0"
}

NODE_RUNTIME=$(detect_node_runtime)

AW_H=(-H "X-Appwrite-Project: $PROJECT_ID" -H "X-Appwrite-Key: $API_KEY")
AW_HJ=("${AW_H[@]}" -H "Content-Type: application/json")

aw_get()  { curl -s "${AW_H[@]}" "$ENDPOINT/$1" 2>&1 || true; }
aw_post() { curl -s -X POST  "${AW_HJ[@]}" -d "$2" "$ENDPOINT/$1" 2>&1 || true; }
aw_put()  { curl -s -X PUT   "${AW_HJ[@]}" -d "$2" "$ENDPOINT/$1" 2>&1 || true; }

has_id() { echo "$1" | grep -q '"\$id"'; }

set_fn_var() {
  local func_id="$1" var_key="$2" var_val="$3"
  local list_res
  list_res=$(aw_get "functions/$func_id/variables")
  local var_id
  var_id=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
for v in data.get('variables', []):
    if v.get('key') == '$var_key':
        print(v.get('\$id',''))
        break
" <<< "$list_res" 2>/dev/null || true)

  local escaped_val
  escaped_val=$(printf '%s' "$var_val" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read())[1:-1])" 2>/dev/null || printf '%s' "$var_val")

  if [[ -n "$var_id" ]]; then
    aw_put "functions/$func_id/variables/$var_id" \
      "{\"key\":\"$var_key\",\"value\":\"$escaped_val\"}" > /dev/null
  else
    aw_post "functions/$func_id/variables" \
      "{\"key\":\"$var_key\",\"value\":\"$escaped_val\"}" > /dev/null
  fi
}

deploy_function() {
  local func_id="$1"
  local func_name="$2"
  local events_json="$3"
  local schedule="$4"
  local timeout="$5"
  shift 5
  local -a vars=("$@")

  local func_dir="$FUNCTIONS_DIR/$func_id"
  echo ""
  echo "=== Deploying: $func_id ==="

  if [[ ! -d "$func_dir" ]]; then
    echo "  ERROR: $func_dir not found"
    exit 1
  fi

  local existing
  existing=$(aw_get "functions/$func_id")

  local enabled_json=true
  if [[ "$func_id" == "daily-preset-pipeline" && "${DAILY_PRESET_PIPELINE_CRON_ENABLED}" != "true" ]]; then
    enabled_json=false
  fi

  local func_body
  func_body=$(printf '%s' "{\"functionId\":\"$func_id\",\"name\":\"$func_name\",\"runtime\":\"${NODE_RUNTIME}\",\"execute\":[],\"events\":$events_json,\"schedule\":\"$schedule\",\"timeout\":$timeout,\"enabled\":${enabled_json},\"logging\":true,\"entrypoint\":\"src/index.js\",\"commands\":\"npm install\"}")

  if has_id "$existing"; then
    echo "  Updating function metadata…"
    aw_put "functions/$func_id" "$func_body" > /dev/null
  else
    echo "  Creating function…"
    local create_res
    create_res=$(aw_post "functions" "$func_body")
    if ! has_id "$create_res"; then
      echo "  ERROR creating function: $create_res"
      exit 1
    fi
    sleep 1
  fi

  echo "  Setting environment variables…"
  local i=0
  while [[ $i -lt ${#vars[@]} ]]; do
    local k="${vars[$i]}"
    local v="${vars[$((i+1))]}"
    echo "    $k"
    set_fn_var "$func_id" "$k" "$v"
    i=$((i + 2))
  done

  local tar_path="/tmp/${func_id}.tar.gz"
  echo "  Packaging → $tar_path"
  if ! (cd "$func_dir" && tar -czf "$tar_path" \
        --exclude='node_modules' --exclude='.appwrite' \
        --exclude='*.tar.gz' . 2>&1); then
    echo "  ERROR: tar failed"
    exit 1
  fi
  echo "  Archive size: $(du -sh "$tar_path" | cut -f1)"

  echo "  Uploading deployment…"
  local deploy_res
  deploy_res=$(curl -s \
    "${AW_H[@]}" \
    -F "code=@${tar_path};type=application/x-gzip" \
    -F "activate=true" \
    -F "entrypoint=src/index.js" \
    -F "commands=npm install" \
    "$ENDPOINT/functions/$func_id/deployments" 2>&1 || true)

  rm -f "$tar_path"

  local deploy_id
  deploy_id=$(echo "$deploy_res" | python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
    print(d.get('\$id',''))
except:
    pass
" 2>/dev/null || true)

  if [[ -n "$deploy_id" ]]; then
    echo "  Deployment ID: $deploy_id"
    echo "  Build started — check Appwrite console for build logs."
    echo "  Done."
  else
    echo "  WARNING: unexpected response from /deployments:"
    echo "  $(echo "$deploy_res" | head -c 500)"
    exit 1
  fi
}

set_public_execute() {
  local func_id="$1"
  local func_name="$2"
  local timeout="$3"
  aw_put "functions/$func_id" \
    "{\"functionId\":\"$func_id\",\"name\":\"$func_name\",\"runtime\":\"${NODE_RUNTIME}\",\"execute\":[\"any\"],\"events\":[],\"schedule\":\"\",\"timeout\":$timeout,\"enabled\":true,\"logging\":true,\"entrypoint\":\"src/index.js\",\"commands\":\"npm install\"}" \
    > /dev/null
  echo "  $func_id execute=[\"any\"] set"
}

DB_EVENTS="[\"databases.${DATABASE_ID}.collections.${PRESETS_COLL}.documents.*.create\",\"databases.${DATABASE_ID}.collections.${PRESETS_COLL}.documents.*.update\"]"
UPDATE_EVENTS="[\"databases.${DATABASE_ID}.collections.${PRESETS_COLL}.documents.*.update\"]"

echo "Endpoint : $ENDPOINT"
echo "Project  : $PROJECT_ID"
echo "Function : $FUNC_ID"
echo "Runtime  : $NODE_RUNTIME"
echo ""

case "$FUNC_ID" in
  verify-trial)
    deploy_function "verify-trial" "Verify Trial" \
      "[]" "" 15 \
      APPWRITE_ENDPOINT    "$ENDPOINT" \
      APPWRITE_PROJECT_ID  "$PROJECT_ID" \
      APPWRITE_API_KEY     "$API_KEY" \
      APPWRITE_DATABASE_ID "$DATABASE_ID"
    set_public_execute "verify-trial" "Verify Trial" 15
    ;;
  apibost-proxy)
    deploy_function "apibost-proxy" "ApiBost Proxy" \
      "[]" "" 600 \
      APPWRITE_ENDPOINT          "$ENDPOINT" \
      APPWRITE_PROJECT_ID        "$PROJECT_ID" \
      APPWRITE_API_KEY           "$API_KEY" \
      APPWRITE_DATABASE_ID       "$DATABASE_ID" \
      APPWRITE_STORAGE_BUCKET_ID "$BUCKET_ID" \
      API_BOST_API_KEY           "$API_BOST_KEY" \
      NL_SERVER_HOST             "$NL_SERVER_HOST" \
      NL_PROXY_TOKEN             "$NL_PROXY_TOKEN" \
      AI_PROXY_PIAPI_PORT        "$AI_PROXY_PIAPI_PORT" \
      YANDEX_AI_RELAY_BASE_URL   "$YANDEX_AI_RELAY_BASE_URL"
    set_public_execute "apibost-proxy" "ApiBost Proxy" 600
    ;;
  verify-rustore-purchase)
    deploy_function "verify-rustore-purchase" "Verify RuStore Purchase" \
      "[]" "" 30 \
      APPWRITE_ENDPOINT    "$ENDPOINT" \
      APPWRITE_PROJECT_ID  "$PROJECT_ID" \
      APPWRITE_API_KEY     "$API_KEY" \
      APPWRITE_DATABASE_ID "$DATABASE_ID" \
      RUSTORE_APP_ID       "$RUSTORE_APP_ID" \
      RUSTORE_KEY_ID       "$RUSTORE_KEY_ID" \
      RUSTORE_PRIVATE_KEY  "$RUSTORE_PRIVATE_KEY" \
      MYTRACKER_S2S_TOKEN  "$MYTRACKER_S2S_TOKEN" \
      MYTRACKER_S2S_APP_ID "$MYTRACKER_S2S_APP_ID"
    set_public_execute "verify-rustore-purchase" "Verify RuStore Purchase" 30
    ;;
  generate-thumbnail)
    deploy_function "generate-thumbnail" "Generate Preset Thumbnail" \
      "$DB_EVENTS" "" 120 \
      APPWRITE_ENDPOINT       "$ENDPOINT" \
      APPWRITE_PROJECT_ID     "$PROJECT_ID" \
      APPWRITE_API_KEY        "$API_KEY" \
      APPWRITE_DATABASE_ID    "$DATABASE_ID" \
      APPWRITE_PRESETS_COLLECTION_ID "$PRESETS_COLL" \
      APPWRITE_STORAGE_BUCKET_ID     "$BUCKET_ID"
    # Клиент вызывает функцию для пресетов, у которых обложки не оказалось
    # после срабатывания события — без публичных прав такой вызов даёт 401.
    aw_put "functions/generate-thumbnail" \
      "{\"functionId\":\"generate-thumbnail\",\"name\":\"Generate Preset Thumbnail\",\"runtime\":\"${NODE_RUNTIME}\",\"execute\":[\"any\"],\"events\":$DB_EVENTS,\"schedule\":\"\",\"timeout\":120,\"enabled\":true,\"logging\":true,\"entrypoint\":\"src/index.js\",\"commands\":\"npm install\"}" \
      > /dev/null
    echo "  generate-thumbnail execute=[\"any\"] set"
    ;;
  process-preset-rewards)
    deploy_function "process-preset-rewards" "Process Preset Rewards" \
      "$UPDATE_EVENTS" "" 60 \
      APPWRITE_ENDPOINT       "$ENDPOINT" \
      APPWRITE_PROJECT_ID     "$PROJECT_ID" \
      APPWRITE_API_KEY        "$API_KEY" \
      APPWRITE_DATABASE_ID    "$DATABASE_ID" \
      APPWRITE_PRESETS_COLLECTION_ID "$PRESETS_COLL" \
      APPWRITE_EARNINGS_COLLECTION_ID "preset_earnings"
    ;;
  repair-preset-permissions)
    deploy_function "repair-preset-permissions" "Repair Preset Permissions" \
      "$DB_EVENTS" "*/5 * * * *" 300 \
      APPWRITE_ENDPOINT       "$ENDPOINT" \
      APPWRITE_PROJECT_ID     "$PROJECT_ID" \
      APPWRITE_API_KEY        "$API_KEY" \
      APPWRITE_DATABASE_ID    "$DATABASE_ID" \
      APPWRITE_PRESETS_COLLECTION_ID "$PRESETS_COLL" \
      APPWRITE_STORAGE_BUCKET_ID     "$BUCKET_ID" \
      REPAIR_PRESET_PERMISSIONS_PAGE_SIZE "50"
    ;;
  daily-preset-pipeline)
    deploy_function "daily-preset-pipeline" "Daily Video Preset Pipeline" \
      "[]" "0 */8 * * *" 900 \
      APPWRITE_ENDPOINT       "$ENDPOINT" \
      APPWRITE_PROJECT_ID     "$PROJECT_ID" \
      APPWRITE_API_KEY        "$API_KEY" \
      APPWRITE_DATABASE_ID    "$DATABASE_ID" \
      APPWRITE_PRESETS_COLLECTION_ID "$PRESETS_COLL" \
      APPWRITE_STORAGE_BUCKET_ID     "$BUCKET_ID" \
      DEEPSEEK_API_KEY        "$DEEPSEEK_KEY" \
      API_BOST_API_KEY        "$API_BOST_KEY" \
      ADMIN_API_KEY           "$ADMIN_KEY" \
      NL_SERVER_HOST          "$NL_SERVER_HOST" \
      NL_PROXY_TOKEN          "$NL_PROXY_TOKEN" \
      AI_PROXY_PIAPI_PORT     "$AI_PROXY_PIAPI_PORT" \
      AI_PROXY_DEEPSEEK_PORT  "$AI_PROXY_DEEPSEEK_PORT" \
      YANDEX_AI_RELAY_BASE_URL "$YANDEX_AI_RELAY_BASE_URL" \
      APIBOST_MODEL           "$(get_env "APIBOST_MODEL" "gemini-3-pro-image-preview")" \
      APIBOST_VIDEO_MODEL     "$(get_env "APIBOST_VIDEO_MODEL" "veo3.1-lite")" \
      DAILY_PRESET_PIPELINE_COUNT "$(get_env "DAILY_PRESET_PIPELINE_COUNT" "1")"
    ;;
  manage-presets)
    deploy_function "manage-presets" "Manage Presets" \
      "[]" "" 900 \
      APPWRITE_ENDPOINT       "$ENDPOINT" \
      APPWRITE_PROJECT_ID     "$PROJECT_ID" \
      APPWRITE_API_KEY        "$API_KEY" \
      APPWRITE_DATABASE_ID    "$DATABASE_ID" \
      APPWRITE_PRESETS_COLLECTION_ID "$PRESETS_COLL" \
      APPWRITE_STORAGE_BUCKET_ID     "$BUCKET_ID" \
      DEEPSEEK_API_KEY        "$DEEPSEEK_KEY" \
      API_BOST_API_KEY        "$API_BOST_KEY" \
      ADMIN_API_KEY           "$ADMIN_KEY" \
      NL_SERVER_HOST          "$NL_SERVER_HOST" \
      NL_PROXY_TOKEN          "$NL_PROXY_TOKEN" \
      AI_PROXY_PIAPI_PORT     "$AI_PROXY_PIAPI_PORT" \
      AI_PROXY_DEEPSEEK_PORT  "$AI_PROXY_DEEPSEEK_PORT" \
      YANDEX_AI_RELAY_BASE_URL "$YANDEX_AI_RELAY_BASE_URL"
    ;;
  ad-creative-generator)
    deploy_function "ad-creative-generator" "Ad Creative Generator" \
      "[]" "" 600 \
      APPWRITE_ENDPOINT              "$ENDPOINT" \
      APPWRITE_PROJECT_ID            "$PROJECT_ID" \
      APPWRITE_API_KEY               "$API_KEY" \
      APPWRITE_STORAGE_BUCKET_ID     "$BUCKET_ID" \
      APPWRITE_AD_CREATIVES_BUCKET_ID "$APPWRITE_AD_CREATIVES_BUCKET_ID" \
      API_BOST_API_KEY               "$API_BOST_KEY" \
      ADMIN_API_KEY                  "$ADMIN_KEY" \
      NL_SERVER_HOST                 "$NL_SERVER_HOST" \
      NL_PROXY_TOKEN                 "$NL_PROXY_TOKEN" \
      AI_PROXY_PIAPI_PORT            "$AI_PROXY_PIAPI_PORT" \
      YANDEX_AI_RELAY_BASE_URL       "$YANDEX_AI_RELAY_BASE_URL"
    set_public_execute "ad-creative-generator" "Ad Creative Generator" 600
    ;;
  *)
    echo "ERROR: unknown function '$FUNC_ID'"
    echo "Run without arguments to see available function ids."
    exit 1
    ;;
esac
