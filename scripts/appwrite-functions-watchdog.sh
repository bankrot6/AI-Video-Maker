#!/bin/bash
# Appwrite Functions Watchdog
#
# Проблема, для которой это написано: openruntimes-executor иногда теряет
# связь с runtime-контейнером конкретной функции ("Internal curl error ...
# Error Number: 52" в логах executor'а — обычно на фоне нехватки памяти/swap).
# После этого новые executions этой функции навечно виснут в статусе
# "waiting" и никогда не запускаются, хотя /v1/health остаётся зелёным
# (поэтому старый appwrite-health.sh это не ловит — он проверяет только
# общий health API, а не реальное выполнение функций).
#
# Это скрипт проверяет последние executions у списка критичных функций.
# Если находит execution с trigger=http и status=waiting старше STUCK_AGE_SEC —
# считает функцию зависшей и перезапускает контейнер openruntimes-executor
# (это самый дёшёвый фикс: он не трогает БД/данные, только сбрасывает
# внутренний пул runtime-контейнеров executor'а).
#
# Дополнительно логирует память/swap каждый цикл, чтобы было видно
# приближение к повторению проблемы (для истории/диагностики).

set -u

APPWRITE_ENDPOINT="http://127.0.0.1/v1"
APPWRITE_PROJECT_ID="6a66f25200139fc454e7"
APPWRITE_API_KEY="${APPWRITE_API_KEY:-}"

# Функции, для которых мониторим зависание executions (самые "тяжёлые" —
# скачивание/загрузка изображений + вызовы AI, чаще всего страдают первыми).
CRITICAL_FUNCTIONS=("apibost-proxy" "daily-preset-pipeline" "ad-creative-generator")

CHECK_INTERVAL=90          # секунд между проверками
STUCK_AGE_SEC=240          # execution в waiting дольше этого — считаем зависшей
# ВАЖНО: restart openruntimes-executor на этом сервере запускает полный
# цикл прогрева всех runtime-образов (Node/PHP/Python/Ruby/...), который
# сам по себе на 20-40 секунд ещё сильнее нагружает и без того забитую
# память. Поэтому cooldown и лимит частоты должны быть консервативными —
# это крайняя мера, а не рутинная операция.
RESTART_COOLDOWN=900       # не перезапускать executor чаще, чем раз в 15 минут
MAX_RESTARTS_PER_HOUR=3

STATE_DIR="/var/lib/appwrite-functions-watchdog"
LOG_FILE="/var/log/appwrite-functions-watchdog.log"

mkdir -p "$STATE_DIR"
touch "$LOG_FILE"

log() {
  # systemd (StandardOutput=append:$LOG_FILE) уже пишет stdout в файл,
  # поэтому просто echo — без tee, иначе строки дублируются в логе.
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$ts] $*"
}

now_epoch() { date +%s; }

iso_to_epoch() {
  # '2026-07-07T00:19:36.386+00:00' -> epoch seconds
  date -d "$1" +%s 2>/dev/null
}

count_recent_restarts() {
  local cutoff_ts count=0
  cutoff_ts=$(( $(now_epoch) - 3600 ))
  if [[ -f "$STATE_DIR/restart_history" ]]; then
    while IFS= read -r ts; do
      [[ "$ts" -ge "$cutoff_ts" ]] && count=$((count + 1))
    done < "$STATE_DIR/restart_history"
  fi
  echo "$count"
}

record_restart() {
  now_epoch >> "$STATE_DIR/restart_history"
  awk -v cutoff="$(( $(now_epoch) - 3600 ))" '$1 >= cutoff' \
    "$STATE_DIR/restart_history" > "$STATE_DIR/restart_history.tmp" 2>/dev/null \
    && mv "$STATE_DIR/restart_history.tmp" "$STATE_DIR/restart_history"
}

last_restart_ts() {
  [[ -f "$STATE_DIR/last_restart" ]] && cat "$STATE_DIR/last_restart" || echo "0"
}

has_stuck_execution() {
  # Важно: смотрим ТОЛЬКО на самую последнюю execution (limit=1, orderDesc).
  # Если сканировать последние N executions, старая зависшая запись
  # (навечно оставшаяся в статусе waiting в истории Appwrite) будет
  # вызывать бесконечный false positive даже после того, как функция
  # уже здорова и новые вызовы проходят нормально.
  local function_id="$1"
  local order_query limit_query response
  order_query=$(python3 -c "import json,urllib.parse; print(urllib.parse.quote(json.dumps({'method':'orderDesc','values':['\$createdAt']})))")
  limit_query=$(python3 -c "import json,urllib.parse; print(urllib.parse.quote(json.dumps({'method':'limit','values':[1]})))")

  response=$(curl -s --max-time 10 \
    "$APPWRITE_ENDPOINT/functions/${function_id}/executions?queries[]=${order_query}&queries[]=${limit_query}" \
    -H "X-Appwrite-Project: $APPWRITE_PROJECT_ID" \
    -H "X-Appwrite-Key: $APPWRITE_API_KEY" 2>/dev/null)

  [[ -z "$response" ]] && return 1

  python3 - "$response" "$STUCK_AGE_SEC" <<'PYEOF'
import json, sys, datetime

data, max_age = sys.argv[1], int(sys.argv[2])
try:
    d = json.loads(data)
except Exception:
    sys.exit(1)

executions = d.get("executions", [])
if not executions:
    sys.exit(1)

e = executions[0]
if e.get("status") != "waiting":
    sys.exit(1)

now = datetime.datetime.now(datetime.timezone.utc)
created = e.get("$createdAt", "")
try:
    ts = datetime.datetime.fromisoformat(created.replace("Z", "+00:00"))
except Exception:
    sys.exit(1)

age = (now - ts).total_seconds()
if age >= max_age:
    print(f"STUCK id={e.get('$id')} age={int(age)}s")
    sys.exit(0)

sys.exit(1)
PYEOF
}

log_memory() {
  local mem_line swap_line
  mem_line=$(free -m | awk '/^Mem:/ {printf "total=%sMB used=%sMB free=%sMB available=%sMB", $2, $3, $4, $7}')
  swap_line=$(free -m | awk '/^Swap:/ {if ($2>0) printf "swap_used_pct=%d%%", ($3*100)/$2; else printf "swap_used_pct=0%%"}')
  log "MEMORY $mem_line $swap_line"
}

restart_executor() {
  local reason="$1"
  local restarts_last_hour
  restarts_last_hour=$(count_recent_restarts)

  if (( restarts_last_hour >= MAX_RESTARTS_PER_HOUR )); then
    log "SKIP restart executor: достигнут лимит $MAX_RESTARTS_PER_HOUR/час (причина: $reason)"
    return 1
  fi

  local last_ts elapsed
  last_ts=$(last_restart_ts)
  elapsed=$(( $(now_epoch) - last_ts ))
  if (( elapsed < RESTART_COOLDOWN )); then
    log "SKIP restart executor: cooldown, прошло ${elapsed}s из ${RESTART_COOLDOWN}s (причина: $reason)"
    return 1
  fi

  log "RESTART openruntimes-executor (причина: $reason)"
  if docker restart openruntimes-executor >> "$LOG_FILE" 2>&1; then
    log "RESTART executor OK"
    now_epoch > "$STATE_DIR/last_restart"
    record_restart
    return 0
  else
    log "RESTART executor FAILED"
    return 1
  fi
}

log "=== Functions Watchdog запущен (pid=$$) ==="

while true; do
  log_memory

  for fid in "${CRITICAL_FUNCTIONS[@]}"; do
    stuck_info=$(has_stuck_execution "$fid")
    if [[ -n "$stuck_info" ]]; then
      log "ЗАВИСШАЯ FUNCTION detected: $fid ($stuck_info)"
      restart_executor "stuck function: $fid ($stuck_info)"
      # После restart executor'а даём время переинициализироваться,
      # не проверяем остальные функции в этом же цикле подряд.
      break
    fi
  done

  sleep "$CHECK_INTERVAL"
done
