#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
DEPLOY_SECRETS_FILE="${DEPLOY_SECRETS_FILE:-$PROJECT_ROOT/.env.deploy}"

get_env() {
  local key="$1" default="${2:-}"
  python3 - "$key" "$default" "$DEPLOY_SECRETS_FILE" "$ENV_FILE" <<'PYEOF'
import re
import sys

key, default = sys.argv[1], sys.argv[2]
for env_file in sys.argv[3:]:
    try:
        with open(env_file, 'r', encoding='utf-8', errors='replace') as f:
            for line in f:
                match = re.match(r'^' + re.escape(key) + r'\s*=\s*(.*)', line.rstrip('\r\n'))
                if match:
                    print(match.group(1).strip('"').strip("'"), end='')
                    sys.exit(0)
    except Exception:
        pass
print(default, end='')
PYEOF
}

SERVER_HOST=$(get_env "SERVER_HOST")
SERVER_PORT=$(get_env "SERVER_SSH_PORT" "22")
SERVER_USER=$(get_env "SERVER_SSH_USER")
SERVER_PASSWORD=$(get_env "SERVER_SSH_PASSWORD")
SERVER_KEY_PATH=$(get_env "SERVER_SSH_KEY_PATH")
NL_SERVER_HOST=$(get_env "NL_SERVER_HOST")
AI_PROXY_PIAPI_PORT=$(get_env "AI_PROXY_PIAPI_PORT" "8080")
AI_PROXY_DEEPSEEK_PORT=$(get_env "AI_PROXY_DEEPSEEK_PORT" "8001")
YANDEX_AI_RELAY_PORT=$(get_env "YANDEX_AI_RELAY_PORT" "8787")

[[ -z "$SERVER_HOST" ]] && { echo "ERROR: SERVER_HOST пустой"; exit 1; }
[[ -z "$SERVER_USER" ]] && { echo "ERROR: SERVER_SSH_USER пустой"; exit 1; }
[[ -z "$NL_SERVER_HOST" ]] && { echo "ERROR: NL_SERVER_HOST пустой"; exit 1; }

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=15 -p "$SERVER_PORT")
SCP_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=15 -P "$SERVER_PORT")

if [[ -n "$SERVER_KEY_PATH" ]]; then
  if [[ ! "$SERVER_KEY_PATH" = /* ]]; then
    SERVER_KEY_PATH="$PROJECT_ROOT/${SERVER_KEY_PATH#./}"
  fi
  if [[ "$SERVER_KEY_PATH" == *.zip ]]; then
    KEY_UNPACK_DIR="$PROJECT_ROOT/temp_check/yandex_ai_relay"
    mkdir -p "$KEY_UNPACK_DIR"
    unzip -o "$SERVER_KEY_PATH" -d "$KEY_UNPACK_DIR" >/dev/null
    SERVER_KEY_PATH=$(python3 - "$KEY_UNPACK_DIR" <<'PYEOF'
import os
import sys

root = sys.argv[1]
for name in os.listdir(root):
    path = os.path.join(root, name)
    if os.path.isfile(path) and not name.endswith('.pub'):
        print(path, end='')
        break
PYEOF
)
    chmod 600 "$SERVER_KEY_PATH"
  fi
  [[ -f "$SERVER_KEY_PATH" ]] || { echo "ERROR: SSH ключ не найден: $SERVER_KEY_PATH"; exit 1; }
  SSH_BASE=(ssh -i "$SERVER_KEY_PATH" "${SSH_OPTS[@]}")
  SCP_BASE=(scp -i "$SERVER_KEY_PATH" "${SCP_OPTS[@]}")
elif [[ -n "$SERVER_PASSWORD" ]]; then
  command -v sshpass >/dev/null 2>&1 || { echo "ERROR: нужен sshpass или SSH ключ"; exit 1; }
  SSH_BASE=(sshpass -p "$SERVER_PASSWORD" ssh "${SSH_OPTS[@]}")
  SCP_BASE=(sshpass -p "$SERVER_PASSWORD" scp "${SCP_OPTS[@]}")
else
  echo "ERROR: не задан ни SERVER_SSH_KEY_PATH, ни SERVER_SSH_PASSWORD"
  exit 1
fi

REMOTE="$SERVER_USER@$SERVER_HOST"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/ai_yandex_relay.py" <<'PYEOF'
#!/usr/bin/env python3
import http.client
import json
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

LISTEN_HOST = os.environ.get("YANDEX_AI_RELAY_BIND", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("YANDEX_AI_RELAY_PORT", "8787"))
UPSTREAM_HOST = os.environ["NL_SERVER_HOST"]
ALLOWED_PORTS = {
    str(int(os.environ.get("AI_PROXY_PIAPI_PORT", "8080"))),
    str(int(os.environ.get("AI_PROXY_DEEPSEEK_PORT", "8001"))),
}

# Генерация фото/песен — долгая (до нескольких минут), но она целиком идёт
# на UPSTREAM-соединении (см. UPSTREAM_TIMEOUT_SEC ниже). Клиентский сокет
# (Appwrite-функция <-> relay) в это время НЕ участвует в I/O — процесс
# просто ждёт ответа upstream, ничего не читая/не записывая на своём конце.
# Поэтому IDLE_TIMEOUT_SEC ниже — это исключительно таймаут "простоя" между
# запросами на переиспользуемом keep-alive соединении, и он никогда не
# прерывает уже идущую генерацию.
IDLE_TIMEOUT_SEC = int(os.environ.get("YANDEX_AI_RELAY_IDLE_TIMEOUT_SEC", "60"))
# Даём upstream-запросу больше времени, чем самый долгий таймаут вызывающей
# Appwrite-функции (apibost-proxy/ad-creative-generator — 600с, generation
# песен может занимать дольше), чтобы relay не обрывал соединение раньше,
# чем сама функция — иначе клиент увидит малопонятный "fetch failed" вместо
# осмысленной ошибки таймаута от самой функции.
UPSTREAM_TIMEOUT_SEC = int(os.environ.get("YANDEX_AI_RELAY_UPSTREAM_TIMEOUT_SEC", "900"))
# Защитный потолок на одновременные соединения. Это НЕ основной фикс утечки
# (её убирает IDLE_TIMEOUT_SEC), а страховка на случай аномального всплеска
# трафика — чтобы процесс не рос потоками без предела при любых будущих
# сюрпризах.
MAX_CONCURRENT_REQUESTS = int(os.environ.get("YANDEX_AI_RELAY_MAX_CONCURRENCY", "300"))

HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "host",
    "content-length",
}

PASSTHROUGH_RESPONSE_HEADERS = {
    "content-type",
    "content-encoding",
    "cache-control",
    "etag",
    "last-modified",
    "content-disposition",
    "x-accel-buffering",
}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    # StreamRequestHandler.timeout — таймаут на операции с КЛИЕНТСКИМ
    # сокетом (чтение запроса / запись ответа / ожидание следующего
    # keep-alive запроса). Раньше был None (ждать бесконечно), из-за чего
    # соединения, которые клиент не закрыл явно (обрыв сети, убитый
    # контейнер Appwrite-функции, зависший NAT), навечно занимали поток —
    # это и есть причина утечки на 1000+ потоков. Долгую генерацию это НЕ
    # трогает: она выполняется на отдельном upstream-соединении, пока
    # клиентский сокет вообще не участвует в I/O (см. комментарий выше).
    timeout = IDLE_TIMEOUT_SEC

    def _send_json(self, code, payload):
        body_bytes = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body_bytes)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, Accept, X-Ai-Proxy-Token, X-Requested-With, x-api-key")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
        self.end_headers()
        self.wfile.write(body_bytes)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, Accept, X-Ai-Proxy-Token, X-Requested-With, x-api-key")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        self._proxy()

    def do_POST(self):
        self._proxy()

    def do_PUT(self):
        self._proxy()

    def do_PATCH(self):
        self._proxy()

    def do_DELETE(self):
        self._proxy()

    def _proxy(self):
        if self.path == "/health":
            self._send_json(200, {"ok": True})
            return

        split = urlsplit(self.path)
        segments = [part for part in split.path.split("/") if part]
        if len(segments) < 2:
            self._send_json(404, {"error": "invalid_path"})
            return

        port = segments[0]
        if port not in ALLOWED_PORTS:
            self._send_json(403, {"error": "port_not_allowed"})
            return

        upstream_path = "/" + "/".join(segments[1:])
        if split.query:
            upstream_path = f"{upstream_path}?{split.query}"

        content_length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(content_length) if content_length > 0 else None

        upstream_headers = {}
        for key, value in self.headers.items():
            lower = key.lower()
            if lower in HOP_HEADERS:
                continue
            upstream_headers[key] = value
        upstream_headers["Host"] = f"{UPSTREAM_HOST}:{port}"
        upstream_headers["Accept-Encoding"] = "identity"

        upstream = http.client.HTTPConnection(
            UPSTREAM_HOST,
            int(port),
            timeout=UPSTREAM_TIMEOUT_SEC,
        )

        # Шаг 1: сходить к upstream. Ошибки здесь (таймаут генерации,
        # недоступность NL-сервера и т.п.) безопасно превращаем в 502 —
        # клиентский сокет на этот момент ещё чист, ничего не отправлено.
        try:
            upstream.request(self.command, upstream_path, body=body, headers=upstream_headers)
            response = upstream.getresponse()
        except Exception as exc:
            upstream.close()
            self._send_json(502, {"error": "upstream_failure", "details": str(exc)})
            return

        # Шаг 2: перегнать ответ клиенту. Ошибки здесь означают, что клиент
        # уже отвалился (BrokenPipe/ConnectionReset/таймаут записи) — в
        # этом случае НЕЛЬЗЯ пытаться отправить JSON с ошибкой (сокет мёртв,
        # это лишь заново кинет исключение); просто тихо закрываем всё.
        try:
            content_type = response.getheader("Content-Type", "")

            self.send_response(response.status, response.reason)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, Accept, X-Ai-Proxy-Token, X-Requested-With, x-api-key")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")

            for key, value in response.getheaders():
                lower = key.lower()
                if lower in HOP_HEADERS:
                    continue
                if lower in PASSTHROUGH_RESPONSE_HEADERS:
                    self.send_header(key, value)

            if "text/event-stream" in content_type:
                # SSE: читаем через read1() — корректно декодирует chunked от
                # upstream (raw readline() ломал поток hex-размерами чанков).
                # Connection: close + close_connection — клиент детектит конец
                # стрима по закрытию сокета, иначе keep-alive подвешивал чтение.
                self.send_header("Cache-Control", "no-cache")
                self.send_header("X-Accel-Buffering", "no")
                self.send_header("Connection", "close")
                self.close_connection = True
                self.end_headers()
                while True:
                    chunk = response.read1(65536)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
                return

            data = response.read()
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            if data:
                self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError, TimeoutError, OSError) as exc:
            self.close_connection = True
            self.log_message("client disconnected mid-response: %s", exc)
        finally:
            upstream.close()


class BoundedThreadingHTTPServer(ThreadingHTTPServer):
    # daemon_threads=True — чтобы возможный будущий чистый shutdown/restart
    # не блокировался зависшими worker-потоками.
    daemon_threads = True

    def __init__(self, *args, max_concurrent_requests=MAX_CONCURRENT_REQUESTS, **kwargs):
        self._capacity = threading.BoundedSemaphore(max_concurrent_requests)
        super().__init__(*args, **kwargs)

    def process_request(self, request, client_address):
        # Защитный потолок на одновременные соединения (страховка сверху
        # над IDLE_TIMEOUT_SEC — тот убирает саму утечку, это лишь предел
        # на случай аномального всплеска трафика). При переполнении сразу
        # закрываем новое соединение, не тратя на него поток.
        if not self._capacity.acquire(blocking=False):
            try:
                request.close()
            except OSError:
                pass
            return
        super().process_request(request, client_address)

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self._capacity.release()


if __name__ == "__main__":
    server = BoundedThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    server.serve_forever()
PYEOF

cat > "$TMP_DIR/yandex-ai-relay.service" <<EOF
[Unit]
Description=Shared Yandex AI relay
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/yandex-ai-relay
Environment=NL_SERVER_HOST=$NL_SERVER_HOST
Environment=AI_PROXY_PIAPI_PORT=$AI_PROXY_PIAPI_PORT
Environment=AI_PROXY_DEEPSEEK_PORT=$AI_PROXY_DEEPSEEK_PORT
Environment=YANDEX_AI_RELAY_PORT=$YANDEX_AI_RELAY_PORT
# Таймаут простоя клиентского keep-alive соединения — НЕ таймаут генерации
# (та ограничена YANDEX_AI_RELAY_UPSTREAM_TIMEOUT_SEC ниже и идёт на другом
# соединении). Это фикс утечки потоков из-за соединений, которые клиент не
# закрыл явно.
Environment=YANDEX_AI_RELAY_IDLE_TIMEOUT_SEC=60
# Таймаут запроса к upstream (NL-сервер) — с запасом покрывает самую долгую
# генерацию фото/песен, дольше максимального таймаута вызывающих Appwrite-
# функций (600-900с), чтобы relay не обрывал раньше самой функции.
Environment=YANDEX_AI_RELAY_UPSTREAM_TIMEOUT_SEC=900
# Защитный потолок на одновременные соединения (страховка сверху, не
# основной фикс).
Environment=YANDEX_AI_RELAY_MAX_CONCURRENCY=300
ExecStart=/usr/bin/python3 /opt/yandex-ai-relay/ai_yandex_relay.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

"${SCP_BASE[@]}" "$TMP_DIR/ai_yandex_relay.py" "$REMOTE:/tmp/ai_yandex_relay.py"
"${SCP_BASE[@]}" "$TMP_DIR/yandex-ai-relay.service" "$REMOTE:/tmp/yandex-ai-relay.service"

"${SSH_BASE[@]}" "$REMOTE" "sudo mkdir -p /opt/yandex-ai-relay && sudo mv /tmp/ai_yandex_relay.py /opt/yandex-ai-relay/ai_yandex_relay.py && sudo chmod 755 /opt/yandex-ai-relay/ai_yandex_relay.py && sudo mv /tmp/yandex-ai-relay.service /etc/systemd/system/yandex-ai-relay.service && sudo systemctl daemon-reload && sudo systemctl enable --now yandex-ai-relay.service && sudo systemctl restart yandex-ai-relay.service && sudo systemctl --no-pager --full status yandex-ai-relay.service | sed -n '1,80p'"

echo "Done: http://$SERVER_HOST:$YANDEX_AI_RELAY_PORT/health"
