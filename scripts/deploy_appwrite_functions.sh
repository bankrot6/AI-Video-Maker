#!/usr/bin/env bash
# Deploy all Appwrite Functions to the self-hosted Appwrite instance.
#
# Usage:
#   bash scripts/deploy_appwrite_functions.sh
#
# Requirements: curl, tar

set -uo pipefail   # -u: fail on unset vars; -o pipefail — NO -e (we handle errors manually)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
DEPLOY_SECRETS_FILE="${DEPLOY_SECRETS_FILE:-$PROJECT_ROOT/.env.deploy}"
FUNCTIONS_DIR="$PROJECT_ROOT/appwrite-functions"

# ─── Load .env + .env.deploy (safe grep — never source the file) ─────────────
[[ ! -f "$ENV_FILE" ]] && { echo "ERROR: .env not found at $ENV_FILE"; exit 1; }

get_env() {
  local key="$1" default="${2:-}"
  local val
  # Сначала .env.deploy (секреты деплоя), потом .env (конфиг приложения)
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
GENERATIONS_COLL=$(get_env "APPWRITE_GENERATIONS_COLLECTION_ID" "user_generations")
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

[[ -z "$ENDPOINT" || -z "$PROJECT_ID" || -z "$API_KEY" ]] && {
  echo "ERROR: APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY must be set in .env"
  exit 1
}

echo "Endpoint : $ENDPOINT"
echo "Project  : $PROJECT_ID"
echo "Database : $DATABASE_ID"
echo "daily-preset-pipeline cron: $([[ "${DAILY_PRESET_PIPELINE_CRON_ENABLED}" == "true" ]] && echo ON || echo OFF) (set DAILY_PRESET_PIPELINE_CRON_ENABLED=true in .env to enable)"
echo ""

# ─── Detect best available Node.js runtime ───────────────────────────────────
detect_node_runtime() {
  local runtimes_json
  # Retry up to 3 times — Appwrite may still be starting
  for attempt in 1 2 3; do
    runtimes_json=$(curl -s --max-time 15 \
      -H "X-Appwrite-Project: $PROJECT_ID" \
      -H "X-Appwrite-Key: $API_KEY" \
      "$ENDPOINT/functions/runtimes" 2>/dev/null || true)
    # Pick highest Node version available (node-20 > node-18 > node-16)
    for candidate in node-20.0 node-18.0 node-16.0; do
      if echo "$runtimes_json" | grep -q "\"$candidate\""; then
        echo "$candidate"
        return
      fi
    done
    [[ $attempt -lt 3 ]] && { echo "  (attempt $attempt: no runtimes yet, waiting 10s…)" >&2; sleep 10; }
  done
  # Fallback: node-18.0 was added to _APP_FUNCTIONS_RUNTIMES by fix script
  echo "node-18.0"
}

NODE_RUNTIME=$(detect_node_runtime)
echo "Node runtime : $NODE_RUNTIME"
echo ""

# ─── Helpers ─────────────────────────────────────────────────────────────────
AW_H=(-H "X-Appwrite-Project: $PROJECT_ID" -H "X-Appwrite-Key: $API_KEY")
AW_HJ=("${AW_H[@]}" -H "Content-Type: application/json")

# All curl helpers return the response body; never fail the script
aw_get()  { curl -s "${AW_H[@]}" "$ENDPOINT/$1" 2>&1 || true; }
aw_post() { curl -s -X POST  "${AW_HJ[@]}" -d "$2" "$ENDPOINT/$1" 2>&1 || true; }
aw_put()  { curl -s -X PUT   "${AW_HJ[@]}" -d "$2" "$ENDPOINT/$1" 2>&1 || true; }
aw_patch(){ curl -s -X PATCH "${AW_HJ[@]}" -d "$2" "$ENDPOINT/$1" 2>&1 || true; }

# Check if JSON response contains '"$id"' (single quotes — no bash expansion of $id)
has_id() { echo "$1" | grep -q '"\$id"'; }

collection_exists() {
  local res
  res=$(aw_get "databases/$DATABASE_ID/collections/$1")
  has_id "$res"
}

create_collection_if_missing() {
  local coll_id="$1" coll_name="$2"
  if collection_exists "$coll_id"; then
    echo "  Collection exists: $coll_id"
  else
    echo "  Creating collection: $coll_id"
    aw_post "databases/$DATABASE_ID/collections" \
      "{\"collectionId\":\"$coll_id\",\"name\":\"$coll_name\",\"permissions\":[\"read(\\\"any\\\")\"]}"\
      > /dev/null
    sleep 1
  fi
}

attribute_exists() {
  local res
  res=$(aw_get "databases/$DATABASE_ID/collections/$1/attributes/$2")
  echo "$res" | grep -q '"key"'
}

create_string_attr() {
  local coll_id="$1" key="$2" size="${3:-256}" required="${4:-false}" array="${5:-false}"
  if ! attribute_exists "$coll_id" "$key"; then
    echo "    + string[$key]"
    aw_post "databases/$DATABASE_ID/collections/$coll_id/attributes/string" \
      "{\"key\":\"$key\",\"size\":$size,\"required\":$required,\"array\":$array}" > /dev/null
    sleep 0.5
  fi
}

create_integer_attr() {
  local coll_id="$1" key="$2" required="${3:-false}"
  if ! attribute_exists "$coll_id" "$key"; then
    echo "    + integer[$key]"
    aw_post "databases/$DATABASE_ID/collections/$coll_id/attributes/integer" \
      "{\"key\":\"$key\",\"required\":$required}" > /dev/null
    sleep 0.5
  fi
}

create_boolean_attr() {
  local coll_id="$1" key="$2" required="${3:-false}"
  if ! attribute_exists "$coll_id" "$key"; then
    echo "    + boolean[$key]"
    aw_post "databases/$DATABASE_ID/collections/$coll_id/attributes/boolean" \
      "{\"key\":\"$key\",\"required\":$required}" > /dev/null
    sleep 0.5
  fi
}

# Set a function environment variable via the variables API
set_fn_var() {
  local func_id="$1" var_key="$2" var_val="$3"
  # Check if variable already exists
  local list_res
  list_res=$(aw_get "functions/$func_id/variables")
  local var_id
  # '"key":"VAR_KEY"' then find the $id nearby — use python for reliable JSON parsing
  var_id=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
for v in data.get('variables', []):
    if v.get('key') == '$var_key':
        print(v.get('\$id',''))
        break
" <<< "$list_res" 2>/dev/null || true)

  # Escape value for JSON — use printf to avoid heredoc trailing newline bug
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

# ─── Schema setup ────────────────────────────────────────────────────────────
echo "=== Schema setup ==="

echo "  Patching presets collection…"
create_string_attr "$PRESETS_COLL" "thumbnailSourceUrl" 2048 false
create_string_attr "$PRESETS_COLL" "sourceChannel"      128  false
create_string_attr "$PRESETS_COLL" "sourcePostId"       64   false
create_boolean_attr "$PRESETS_COLL" "isPublic"          false
create_string_attr  "$PRESETS_COLL" "ownerId"           128  false
create_string_attr  "$PRESETS_COLL" "appwriteUserId"    64   false

create_collection_if_missing "preset_earnings" "Preset Earnings"
echo "  Patching preset_earnings…"
create_string_attr  "preset_earnings" "presetId"           64  false
create_string_attr  "preset_earnings" "ownerId"            128 false
create_integer_attr "preset_earnings" "totalLikes"
create_integer_attr "preset_earnings" "creditsEarned"
create_integer_attr "preset_earnings" "lastProcessedLikes"
create_string_attr  "preset_earnings" "lastProcessedAt"    64  false
create_string_attr  "preset_earnings" "createdAt"          64  false

create_collection_if_missing "pipeline_state" "Pipeline State"
echo "  Patching pipeline_state…"
create_string_attr "pipeline_state" "clickpickstyle" 512 false true
create_string_attr "pipeline_state" "photosesser"    512 false true
create_string_attr "pipeline_state" "updatedAt"      64  false

create_collection_if_missing "trial_registry" "Trial Registry"
echo "  Patching trial_registry…"
create_string_attr "trial_registry" "fingerprint" 64  true
create_string_attr "trial_registry" "platform"    16  false
create_string_attr "trial_registry" "claimedAt"   64  false

create_collection_if_missing "device_registry" "Device Registry"
echo "  Patching device_registry…"
create_string_attr  "device_registry" "fingerprint"        64  true
create_string_attr  "device_registry" "platform"           16  false
create_string_attr  "device_registry" "firstSeenAt"        64  true
create_integer_attr "device_registry" "freeCreditsUsed"     false
create_integer_attr "device_registry" "freeGenerationsUsed" false
create_integer_attr "device_registry" "purchasedCredits"    false
create_integer_attr "device_registry" "earnedCredits"       false
create_integer_attr "device_registry" "currentBalance"      false
create_string_attr  "device_registry" "subscriptionType"    16 false

create_collection_if_missing "rustore_purchase_ledger" "RuStore Purchase Ledger"
echo "  Patching rustore_purchase_ledger…"
create_string_attr  "rustore_purchase_ledger" "purchaseId"            64  true
create_string_attr  "rustore_purchase_ledger" "invoiceId"             64  true
create_string_attr  "rustore_purchase_ledger" "orderId"               150 false
create_string_attr  "rustore_purchase_ledger" "fingerprint"           64  true
create_string_attr  "rustore_purchase_ledger" "productId"             128 true
create_integer_attr "rustore_purchase_ledger" "creditsGranted"        false
create_string_attr  "rustore_purchase_ledger" "store"                 16  true
create_string_attr  "rustore_purchase_ledger" "status"                32  true
create_string_attr  "rustore_purchase_ledger" "platform"              16  false
create_string_attr  "rustore_purchase_ledger" "purchaseState"         32  false
create_string_attr  "rustore_purchase_ledger" "acknowledgementState"  32  false
create_string_attr  "rustore_purchase_ledger" "createdAt"             64  true
create_string_attr  "rustore_purchase_ledger" "updatedAt"             64  true

echo "  Waiting 3s for attribute propagation…"
sleep 3

# Индекс по fingerprint для быстрого поиска (создаём один раз)
echo "  Ensuring index on trial_registry.fingerprint…"
INDEX_CHECK=$(aw_get "databases/$DATABASE_ID/collections/trial_registry/indexes/fingerprint_idx")
if ! echo "$INDEX_CHECK" | grep -q '"key"'; then
  aw_post "databases/$DATABASE_ID/collections/trial_registry/indexes" \
    '{"key":"fingerprint_idx","type":"unique","attributes":["fingerprint"]}' > /dev/null
  echo "    + index[fingerprint_idx] created"
else
  echo "    index[fingerprint_idx] exists"
fi

echo "  Ensuring index on device_registry.fingerprint…"
INDEX_CHECK2=$(aw_get "databases/$DATABASE_ID/collections/device_registry/indexes/fingerprint_idx")
if ! echo "$INDEX_CHECK2" | grep -q '"key"'; then
  aw_post "databases/$DATABASE_ID/collections/device_registry/indexes" \
    '{"key":"fingerprint_idx","type":"unique","attributes":["fingerprint"]}' > /dev/null
  echo "    + index[fingerprint_idx] created"
else
  echo "    index[fingerprint_idx] exists"
fi
echo "  Ensuring index on rustore_purchase_ledger.purchaseId…"
INDEX_CHECK3=$(aw_get "databases/$DATABASE_ID/collections/rustore_purchase_ledger/indexes/purchase_idx")
if ! echo "$INDEX_CHECK3" | grep -q '"key"'; then
  aw_post "databases/$DATABASE_ID/collections/rustore_purchase_ledger/indexes" \
    '{"key":"purchase_idx","type":"unique","attributes":["purchaseId"]}' > /dev/null
  echo "    + index[purchase_idx] created"
else
  echo "    index[purchase_idx] exists"
fi
sleep 2

# ─── Function deployment ─────────────────────────────────────────────────────
deploy_function() {
  local func_id="$1"
  local func_name="$2"
  local events_json="$3"
  local schedule="$4"
  local timeout="$5"
  shift 5
  # Remaining args: KEY VALUE KEY VALUE ...
  local -a vars=("$@")

  local func_dir="$FUNCTIONS_DIR/$func_id"
  echo ""
  echo "=== Deploying: $func_id ==="

  if [[ ! -d "$func_dir" ]]; then
    echo "  SKIP: $func_dir not found"
    return 0
  fi

  # ── Create or update function ──────────────────────────────────────────────
  local existing
  existing=$(aw_get "functions/$func_id")

  local enabled_json=true
  if [[ "$func_id" == "daily-preset-pipeline" && "${DAILY_PRESET_PIPELINE_CRON_ENABLED}" != "true" ]]; then
    enabled_json=false
  fi

  local func_body
  func_body=$(printf '%s' "{\"functionId\":\"$func_id\",\"name\":\"$func_name\",\"runtime\":\"${NODE_RUNTIME:-node-18.0}\",\"execute\":[],\"events\":$events_json,\"schedule\":\"$schedule\",\"timeout\":$timeout,\"enabled\":${enabled_json},\"logging\":true,\"entrypoint\":\"src/index.js\",\"commands\":\"npm install\"}")

  if has_id "$existing"; then
    echo "  Updating function metadata…"
    aw_put "functions/$func_id" "$func_body" > /dev/null
  else
    echo "  Creating function…"
    local create_res
    create_res=$(aw_post "functions" "$func_body")
    if ! has_id "$create_res"; then
      echo "  ERROR creating function: $create_res"
      return 0
    fi
    sleep 1
  fi

  # ── Set environment variables ─────────────────────────────────────────────
  echo "  Setting environment variables…"
  local i=0
  while [[ $i -lt ${#vars[@]} ]]; do
    local k="${vars[$i]}"
    local v="${vars[$((i+1))]}"
    echo "    $k"
    set_fn_var "$func_id" "$k" "$v"
    i=$((i + 2))
  done

  # ── Package source code ────────────────────────────────────────────────────
  local tar_path="/tmp/${func_id}.tar.gz"
  echo "  Packaging → $tar_path"
  if ! (cd "$func_dir" && tar -czf "$tar_path" \
        --exclude='node_modules' --exclude='.appwrite' \
        --exclude='*.tar.gz' . 2>&1); then
    echo "  ERROR: tar failed"
    return 0
  fi
  echo "  Archive size: $(du -sh "$tar_path" | cut -f1)"

  # ── Upload deployment ──────────────────────────────────────────────────────
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

  # Parse deployment ID — use single quotes in grep so $id is literal
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
  fi
}

# ─── Deploy each function ─────────────────────────────────────────────────────

DB_EVENTS="[\"databases.${DATABASE_ID}.collections.${PRESETS_COLL}.documents.*.create\",\"databases.${DATABASE_ID}.collections.${PRESETS_COLL}.documents.*.update\"]"
UPDATE_EVENTS="[\"databases.${DATABASE_ID}.collections.${PRESETS_COLL}.documents.*.update\"]"

deploy_function "generate-thumbnail" "Generate Preset Thumbnail" \
  "$DB_EVENTS" "" 120 \
  APPWRITE_ENDPOINT       "$ENDPOINT" \
  APPWRITE_PROJECT_ID     "$PROJECT_ID" \
  APPWRITE_API_KEY        "$API_KEY" \
  APPWRITE_DATABASE_ID    "$DATABASE_ID" \
  APPWRITE_PRESETS_COLLECTION_ID "$PRESETS_COLL" \
  APPWRITE_STORAGE_BUCKET_ID     "$BUCKET_ID"

deploy_function "process-preset-rewards" "Process Preset Rewards" \
  "$UPDATE_EVENTS" "" 60 \
  APPWRITE_ENDPOINT       "$ENDPOINT" \
  APPWRITE_PROJECT_ID     "$PROJECT_ID" \
  APPWRITE_API_KEY        "$API_KEY" \
  APPWRITE_DATABASE_ID    "$DATABASE_ID" \
  APPWRITE_PRESETS_COLLECTION_ID "$PRESETS_COLL" \
  APPWRITE_EARNINGS_COLLECTION_ID "preset_earnings"

deploy_function "repair-preset-permissions" "Repair Preset Permissions" \
  "$DB_EVENTS" "*/5 * * * *" 300 \
  APPWRITE_ENDPOINT       "$ENDPOINT" \
  APPWRITE_PROJECT_ID     "$PROJECT_ID" \
  APPWRITE_API_KEY        "$API_KEY" \
  APPWRITE_DATABASE_ID    "$DATABASE_ID" \
  APPWRITE_PRESETS_COLLECTION_ID "$PRESETS_COLL" \
  APPWRITE_GENERATIONS_COLLECTION_ID "$GENERATIONS_COLL" \
  REPAIR_PRESET_PERMISSIONS_PAGE_SIZE "50"

deploy_function "daily-preset-pipeline" "Daily Video Preset Pipeline" \
  "[]" "0 */8 * * *" 900 \
  APPWRITE_ENDPOINT       "$ENDPOINT" \
  APPWRITE_PROJECT_ID     "$PROJECT_ID" \
  APPWRITE_API_KEY        "$API_KEY" \
  APPWRITE_DATABASE_ID    "$DATABASE_ID" \
  APPWRITE_PRESETS_COLLECTION_ID "$PRESETS_COLL" \
  APPWRITE_STORAGE_BUCKET_ID     "$BUCKET_ID" \
  API_BOST_API_KEY        "$API_BOST_KEY" \
  DEEPSEEK_API_KEY        "$DEEPSEEK_KEY" \
  NL_SERVER_HOST          "$NL_SERVER_HOST" \
  NL_PROXY_TOKEN          "$NL_PROXY_TOKEN" \
  AI_PROXY_PIAPI_PORT     "$AI_PROXY_PIAPI_PORT" \
  AI_PROXY_DEEPSEEK_PORT  "$AI_PROXY_DEEPSEEK_PORT" \
  YANDEX_AI_RELAY_BASE_URL "$YANDEX_AI_RELAY_BASE_URL" \
  APIBOST_MODEL           "$(get_env "APIBOST_MODEL" "gemini-3-pro-image-preview")" \
  APIBOST_VIDEO_MODEL     "$(get_env "APIBOST_VIDEO_MODEL" "veo3.1-lite")" \
  DAILY_PRESET_PIPELINE_COUNT "$(get_env "DAILY_PRESET_PIPELINE_COUNT" "1")"

deploy_function "manage-presets" "Manage Presets" \
  "[]" "" 900 \
  APPWRITE_ENDPOINT       "$ENDPOINT" \
  APPWRITE_PROJECT_ID     "$PROJECT_ID" \
  APPWRITE_API_KEY        "$API_KEY" \
  APPWRITE_DATABASE_ID    "$DATABASE_ID" \
  APPWRITE_PRESETS_COLLECTION_ID "$PRESETS_COLL" \
  APPWRITE_STORAGE_BUCKET_ID     "$BUCKET_ID" \
  API_BOST_API_KEY        "$API_BOST_KEY" \
  DEEPSEEK_API_KEY        "$DEEPSEEK_KEY" \
  ADMIN_API_KEY           "$ADMIN_KEY" \
  NL_SERVER_HOST          "$NL_SERVER_HOST" \
  NL_PROXY_TOKEN          "$NL_PROXY_TOKEN" \
  AI_PROXY_PIAPI_PORT     "$AI_PROXY_PIAPI_PORT" \
  AI_PROXY_DEEPSEEK_PORT  "$AI_PROXY_DEEPSEEK_PORT" \
  YANDEX_AI_RELAY_BASE_URL "$YANDEX_AI_RELAY_BASE_URL"

deploy_function "verify-trial" "Verify Trial" \
  "[]" "" 15 \
  APPWRITE_ENDPOINT    "$ENDPOINT" \
  APPWRITE_PROJECT_ID  "$PROJECT_ID" \
  APPWRITE_API_KEY     "$API_KEY" \
  APPWRITE_DATABASE_ID "$DATABASE_ID"

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

deploy_function "ad-creative-generator" "Ad Creative Generator" \
  "[]" "" 600 \
  APPWRITE_ENDPOINT               "$ENDPOINT" \
  APPWRITE_PROJECT_ID             "$PROJECT_ID" \
  APPWRITE_API_KEY                "$API_KEY" \
  APPWRITE_STORAGE_BUCKET_ID      "$BUCKET_ID" \
  APPWRITE_AD_CREATIVES_BUCKET_ID "$APPWRITE_AD_CREATIVES_BUCKET_ID" \
  API_BOST_API_KEY                "$API_BOST_KEY" \
  ADMIN_API_KEY                   "$ADMIN_KEY" \
  NL_SERVER_HOST                  "$NL_SERVER_HOST" \
  NL_PROXY_TOKEN                  "$NL_PROXY_TOKEN" \
  AI_PROXY_PIAPI_PORT             "$AI_PROXY_PIAPI_PORT" \
  YANDEX_AI_RELAY_BASE_URL        "$YANDEX_AI_RELAY_BASE_URL"

deploy_function "verify-rustore-purchase" "Verify RuStore Purchase" \
  "[]" "" 30 \
  APPWRITE_ENDPOINT    "$ENDPOINT" \
  APPWRITE_PROJECT_ID  "$PROJECT_ID" \
  APPWRITE_API_KEY     "$API_KEY" \
  APPWRITE_DATABASE_ID "$DATABASE_ID" \
  RUSTORE_APP_ID       "$RUSTORE_APP_ID" \
  RUSTORE_KEY_ID       "$RUSTORE_KEY_ID" \
  RUSTORE_PRIVATE_KEY  "$RUSTORE_PRIVATE_KEY"

# Открываем execute-права для всех (клиентский SDK без авторизации)
echo ""
echo "=== Setting execute permissions for generate-thumbnail, verify-trial, apibost-proxy, ad-creative-generator and verify-rustore-purchase ==="
aw_put "functions/generate-thumbnail" \
  "{\"functionId\":\"generate-thumbnail\",\"name\":\"Generate Preset Thumbnail\",\"runtime\":\"${NODE_RUNTIME}\",\"execute\":[\"any\"],\"events\":$DB_EVENTS,\"schedule\":\"\",\"timeout\":120,\"enabled\":true,\"logging\":true,\"entrypoint\":\"src/index.js\",\"commands\":\"npm install\"}" \
  > /dev/null
echo "  generate-thumbnail execute=[\"any\"] set"

aw_put "functions/verify-trial" \
  "{\"functionId\":\"verify-trial\",\"name\":\"Verify Trial\",\"runtime\":\"${NODE_RUNTIME}\",\"execute\":[\"any\"],\"events\":[],\"schedule\":\"\",\"timeout\":15,\"enabled\":true,\"logging\":true,\"entrypoint\":\"src/index.js\",\"commands\":\"npm install\"}" \
  > /dev/null
echo "  verify-trial execute=[\"any\"] set"

aw_put "functions/apibost-proxy" \
  "{\"functionId\":\"apibost-proxy\",\"name\":\"ApiBost Proxy\",\"runtime\":\"${NODE_RUNTIME}\",\"execute\":[\"any\"],\"events\":[],\"schedule\":\"\",\"timeout\":600,\"enabled\":true,\"logging\":true,\"entrypoint\":\"src/index.js\",\"commands\":\"npm install\"}" \
  > /dev/null
echo "  apibost-proxy execute=[\"any\"] set"

aw_put "functions/ad-creative-generator" \
  "{\"functionId\":\"ad-creative-generator\",\"name\":\"Ad Creative Generator\",\"runtime\":\"${NODE_RUNTIME}\",\"execute\":[\"any\"],\"events\":[],\"schedule\":\"\",\"timeout\":600,\"enabled\":true,\"logging\":true,\"entrypoint\":\"src/index.js\",\"commands\":\"npm install\"}" \
  > /dev/null
echo "  ad-creative-generator execute=[\"any\"] set"

aw_put "functions/verify-rustore-purchase" \
  "{\"functionId\":\"verify-rustore-purchase\",\"name\":\"Verify RuStore Purchase\",\"runtime\":\"${NODE_RUNTIME}\",\"execute\":[\"any\"],\"events\":[],\"schedule\":\"\",\"timeout\":30,\"enabled\":true,\"logging\":true,\"entrypoint\":\"src/index.js\",\"commands\":\"npm install\"}" \
  > /dev/null
echo "  verify-rustore-purchase execute=[\"any\"] set"

# ─── Права доступа: коллекции и бакет ────────────────────────────────────────
# Позволяет клиентскому SDK работать без API-ключа (анонимная сессия).
echo ""
echo "=== Setting Appwrite permissions (collections + bucket) ==="

# Используем Node SDK (не curl) — Appwrite REST API игнорирует create-права через PUT
node -e "
const { Client, Databases, Storage, Permission, Role } = require('node-appwrite');
const client = new Client()
  .setEndpoint('$ENDPOINT')
  .setProject('$PROJECT_ID')
  .setKey('$API_KEY');
const db = new Databases(client);
const st = new Storage(client);

async function fixColl(id, perms, docSec) {
  const info = await db.getCollection('$DATABASE_ID', id);
  const r = await db.updateCollection('$DATABASE_ID', id, info.name, perms, docSec);
  console.log('  ' + id + ' →', JSON.stringify(r['\$permissions']));
}
async function fixBucket(id, perms) {
  const info = await st.getBucket(id);
  const r = await st.updateBucket(id, info.name, perms, true);
  console.log('  bucket/' + id + ' →', JSON.stringify(r['\$permissions']));
}

(async () => {
  await fixColl('$PRESETS_COLL',     [Permission.read(Role.any()), Permission.create(Role.users())], true);
  await fixColl('$GENERATIONS_COLL', [Permission.read(Role.any()), Permission.create(Role.any())], true);
  await fixBucket('$BUCKET_ID',      [Permission.read(Role.any()), Permission.create(Role.any())]);
})().catch(e => { console.error('ERROR:', e.message); process.exit(1); });
" 2>/dev/null || {
  echo "  WARNING: node-appwrite not installed, skipping permission setup"
  echo "  Run: npm install -g node-appwrite && bash scripts/deploy_appwrite_functions.sh"
}

echo ""
echo "=== All functions deployed! ==="
echo ""
echo "Endpoints (header required: X-Admin-API-Key: $ADMIN_KEY):"
echo "  POST <manage-presets-url>/           → create preset"
echo "  POST <manage-presets-url>/batch      → batch create"
echo "  POST <manage-presets-url>/backfill   → backfill thumbnails"
echo "  POST <manage-presets-url>/pipeline   → run pipeline {\"limit\":1}"
echo ""
echo "ApiBost Proxy (public, no auth required):"
echo "  POST <apibost-proxy-url>/            → generate image via ApiBost"
echo ""
echo "Ad Creative Generator (public execution, admin key required in request):"
echo "  POST <ad-creative-generator-url>/    → generate VK ad before/after image"
