#!/usr/bin/env bash
# ============================================================
# Серверный скрипт AI nginx-прокси
# Путь на сервере : /opt/ai-proxy/deploy.sh
#
# Запуск на сервере:
#   bash /opt/ai-proxy/deploy.sh
#
# Обновить с рабочей машины (любой проект):
#   bash scripts/deploy_nginx_ai_proxy.sh
#
# Добавить новый маршрут:
#   1. Отредактируй этот файл в Photosession-AI/scripts/server/
#   2. Запусти: bash Photosession-AI/scripts/deploy_nginx_ai_proxy.sh
# ============================================================
set -euo pipefail

SECRETS="/opt/ai-proxy/secrets.env"

if [[ ! -f "$SECRETS" ]]; then
    echo "❌  Файл секретов не найден: $SECRETS"
    echo "    Инициализируй сервер с рабочей машины:"
    echo "    bash Photosession-AI/scripts/deploy_nginx_ai_proxy.sh --init"
    exit 1
fi

# shellcheck source=/dev/null
set -a; source "$SECRETS"; set +a

: "${NL_PROXY_TOKEN:?NL_PROXY_TOKEN не задан в $SECRETS}"

PIAPI_PORT="${AI_PROXY_PIAPI_PORT:-8080}"
DEEPSEEK_PORT="${AI_PROXY_DEEPSEEK_PORT:-8001}"
IMGPROXY_PORT=8002
DEEPSEEK_CLAMP_PORT=8005
APIBOST_RELAY_PORT=8006
APIBOST_API_KEY="${API_BOST_API_KEY:-}"
DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY:-}"
PIAPI_API_KEY="${PIAPI_API_KEY:-}"

echo "▶  Обновляем ai-deepseek-clamp (Python, порт ${DEEPSEEK_CLAMP_PORT})"
mkdir -p /opt/ai-deepseek-clamp
cat > /opt/ai-deepseek-clamp/server.py <<'PYEOF'
#!/usr/bin/env python3
import http.client
import json
import os
import sys
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = int(os.environ.get("DEEPSEEK_CLAMP_PORT", "8005"))
UPSTREAM_HOST = "api.deepseek.com"
UPSTREAM_PATH = "/chat/completions"
API_KEY = os.environ["DEEPSEEK_API_KEY"]
FLASH_MODEL = "deepseek-v4-flash"


def normalize_reasoning_effort(value):
    effort = str(value or "").strip().lower()
    if effort in {"max", "xhigh"}:
        return "max"
    if effort in {"high", "medium", "low"}:
        return "high"
    return ""


def normalize_payload(payload):
    normalized = dict(payload or {})
    normalized["model"] = FLASH_MODEL

    thinking = normalized.get("thinking")
    requested_type = ""
    if isinstance(thinking, dict):
        requested_type = str(thinking.get("type") or "").strip().lower()

    if requested_type in {"enabled", "disabled"}:
        normalized["thinking"] = {"type": requested_type}
        if requested_type == "enabled":
            normalized["reasoning_effort"] = (
                normalize_reasoning_effort(normalized.get("reasoning_effort")) or "high"
            )
        else:
            normalized.pop("reasoning_effort", None)
    else:
        normalized["thinking"] = {"type": "disabled"}
        normalized.pop("reasoning_effort", None)

    return normalized


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _json(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._json(200, {"ok": True, "model": FLASH_MODEL})
            return
        self._json(404, {"error": "not_found"})

    def do_POST(self):
        if self.path != UPSTREAM_PATH:
            self._json(404, {"error": "not_found"})
            return

        length = int(self.headers.get("Content-Length", "0") or "0")
        raw_body = self.rfile.read(length) if length > 0 else b"{}"
        try:
            payload = json.loads(raw_body.decode("utf-8"))
        except json.JSONDecodeError:
            self._json(400, {"error": "invalid_json"})
            return

        normalized_payload = normalize_payload(payload)
        payload_bytes = json.dumps(normalized_payload, ensure_ascii=False).encode("utf-8")

        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {API_KEY}",
            "Accept-Encoding": "identity",
        }
        accept = self.headers.get("Accept")
        if accept:
            headers["Accept"] = accept

        upstream = http.client.HTTPSConnection(UPSTREAM_HOST, timeout=600)
        try:
            upstream.request("POST", UPSTREAM_PATH, body=payload_bytes, headers=headers)
            response = upstream.getresponse()
            content_type = response.getheader("Content-Type", "application/json")

            self.send_response(response.status, response.reason)
            self.send_header("Content-Type", content_type)

            if "text/event-stream" in content_type:
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "keep-alive")
                self.end_headers()
                while True:
                    chunk = response.fp.readline()
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
        except Exception as exc:
            sys.stderr.write(f"[deepseek-clamp] {exc}\n")
            traceback.print_exc(file=sys.stderr)
            self._json(502, {"error": "upstream_failure", "details": str(exc)})
        finally:
            upstream.close()

    def log_message(self, fmt, *args):
        sys.stderr.write(f"[deepseek-clamp] {self.address_string()} - {fmt % args}\n")


if __name__ == "__main__":
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    sys.stderr.write(
        f"[deepseek-clamp] listening on {LISTEN_HOST}:{LISTEN_PORT}, upstream={UPSTREAM_HOST}{UPSTREAM_PATH}\n"
    )
    server.serve_forever()
PYEOF
chmod 755 /opt/ai-deepseek-clamp/server.py

cat > /etc/systemd/system/ai-deepseek-clamp.service <<EOF
[Unit]
Description=DeepSeek Flash Clamp Proxy
After=network.target

[Service]
Type=simple
EnvironmentFile=/opt/ai-proxy/secrets.env
Environment=DEEPSEEK_CLAMP_PORT=${DEEPSEEK_CLAMP_PORT}
ExecStart=/usr/bin/python3 /opt/ai-deepseek-clamp/server.py
Restart=always
RestartSec=2
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ai-deepseek-clamp

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ai-deepseek-clamp >/dev/null 2>&1 || true
systemctl restart ai-deepseek-clamp
sleep 1
systemctl is-active --quiet ai-deepseek-clamp && echo "   ai-deepseek-clamp запущен" || {
    echo "❌  ai-deepseek-clamp не стартовал"
    systemctl --no-pager --full status ai-deepseek-clamp || true
    exit 1
}

echo "▶  Обновляем ai-apibost-relay (Python, порт ${APIBOST_RELAY_PORT})"
if [[ ! -f /opt/ai-apibost-relay/server.py ]]; then
    echo "❌  /opt/ai-apibost-relay/server.py не найден"
    echo "    Запусти deploy с рабочей машины: bash scripts/deploy_nginx_ai_proxy.sh"
    exit 1
fi
chmod 755 /opt/ai-apibost-relay/server.py

cat > /etc/systemd/system/ai-apibost-relay.service <<EOF
[Unit]
Description=ApiBost relay (preview to 3.1 GA, 3.1 fallback to 2.5)
After=network.target

[Service]
Type=simple
EnvironmentFile=/opt/ai-proxy/secrets.env
Environment=APIBOST_RELAY_PORT=${APIBOST_RELAY_PORT}
ExecStart=/usr/bin/python3 /opt/ai-apibost-relay/server.py
Restart=always
RestartSec=2
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ai-apibost-relay

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ai-apibost-relay >/dev/null 2>&1 || true
systemctl restart ai-apibost-relay
sleep 1
systemctl is-active --quiet ai-apibost-relay && echo "   ai-apibost-relay запущен" || {
    echo "❌  ai-apibost-relay не стартовал"
    systemctl --no-pager --full status ai-apibost-relay || true
    exit 1
}

echo "▶  Генерируем /etc/nginx/conf.d/ai-proxy.conf"
echo "   Токен : ${NL_PROXY_TOKEN:0:4}****${NL_PROXY_TOKEN: -4}"
echo "   PiAPI : порт $PIAPI_PORT"
echo "   DS    : порт $DEEPSEEK_PORT"

# ─── Формируем конфиг ───────────────────────────────────────
# Nginx-переменные ($deepseek_allowed и т.п.) экранированы \$,
# shell-переменные (${NL_PROXY_TOKEN} и т.п.) интерполируются здесь.
NGINX_CONF="# AI-прокси для обхода гео-блокировок (нидерландский сервер)
# АВТОГЕНЕРИРУЕТСЯ — не редактировать вручную.
# Управляется: /opt/ai-proxy/deploy.sh
# Обновить: bash Photosession-AI/scripts/deploy_nginx_ai_proxy.sh

# ── Порт ${PIAPI_PORT}: PiAPI · ApiBost · ElevenLabs · Google APIs · VK ─────
server {
    listen ${PIAPI_PORT};
    listen [::]:${PIAPI_PORT};
    server_name _;

    resolver 8.8.8.8 valid=60s ipv6=off;

    client_max_body_size 20m;
    client_header_buffer_size 4k;
    large_client_header_buffers 8 32k;
    proxy_buffering off;

    # Запросы без токен-префикса отклоняются
    location /ai-${NL_PROXY_TOKEN}/piapi/ {
        proxy_pass         https://api.piapi.ai/;
        proxy_ssl_server_name on;
        proxy_set_header   Host api.piapi.ai;
        proxy_pass_request_headers on;
        proxy_set_header   X-API-Key "${PIAPI_API_KEY}";
        proxy_read_timeout 300s;
        proxy_connect_timeout 30s;
        proxy_send_timeout  60s;
    }

    location /ai-${NL_PROXY_TOKEN}/piapi-upload/ {
        proxy_pass         https://upload.theapi.app/;
        proxy_ssl_server_name on;
        proxy_set_header   Host upload.theapi.app;
        proxy_pass_request_headers on;
        proxy_set_header   x-api-key "${PIAPI_API_KEY}";
        proxy_read_timeout 120s;
        proxy_connect_timeout 30s;
        proxy_send_timeout 120s;
    }

    location /ai-${NL_PROXY_TOKEN}/apibost/ {
        proxy_pass         http://127.0.0.1:${APIBOST_RELAY_PORT}/;
        proxy_http_version 1.1;
        proxy_set_header   Host apibost.com;
        proxy_pass_request_headers on;
        proxy_read_timeout 420s;
        proxy_connect_timeout 30s;
        proxy_send_timeout  120s;
    }

    location /ai-${NL_PROXY_TOKEN}/elevenlabs/ {
        proxy_pass         https://api.elevenlabs.io/;
        proxy_ssl_server_name on;
        proxy_set_header   Host api.elevenlabs.io;
        proxy_pass_request_headers on;
        proxy_read_timeout 120s;
        proxy_connect_timeout 30s;
        proxy_send_timeout  60s;
    }

    location /ai-${NL_PROXY_TOKEN}/suno/ {
        proxy_pass         https://api.sunoapi.org/;
        proxy_ssl_server_name on;
        proxy_set_header   Host api.sunoapi.org;
        proxy_pass_request_headers on;
        proxy_set_header   User-Agent "Application";
        proxy_set_header   Accept "application/json";
        proxy_read_timeout 420s;
        proxy_connect_timeout 30s;
        proxy_send_timeout  120s;
    }

    location /ai-${NL_PROXY_TOKEN}/suno-voice-callback/ {
        proxy_pass         http://127.0.0.1:8004/;
        proxy_http_version 1.1;
        proxy_read_timeout 60s;
        proxy_connect_timeout 10s;
        proxy_send_timeout  60s;
        proxy_pass_request_headers on;
    }

    location /ai-${NL_PROXY_TOKEN}/google-cse/ {
        proxy_pass         https://customsearch.googleapis.com/;
        proxy_ssl_server_name on;
        proxy_set_header   Host customsearch.googleapis.com;
        proxy_pass_request_headers on;
        proxy_read_timeout 90s;
        proxy_connect_timeout 30s;
        proxy_send_timeout  60s;
    }

    location /ai-${NL_PROXY_TOKEN}/google-speech/ {
        proxy_pass         https://speech.googleapis.com/;
        proxy_ssl_server_name on;
        proxy_set_header   Host speech.googleapis.com;
        proxy_pass_request_headers on;
        proxy_read_timeout 90s;
        proxy_connect_timeout 30s;
        proxy_send_timeout  90s;
    }

    location /ai-${NL_PROXY_TOKEN}/google-tts/ {
        proxy_pass         https://texttospeech.googleapis.com/;
        proxy_ssl_server_name on;
        proxy_set_header   Host texttospeech.googleapis.com;
        proxy_pass_request_headers on;
        proxy_read_timeout 90s;
        proxy_connect_timeout 30s;
        proxy_send_timeout  60s;
    }

    location /ai-${NL_PROXY_TOKEN}/google-maps/ {
        proxy_pass         https://maps.googleapis.com/;
        proxy_ssl_server_name on;
        proxy_set_header   Host maps.googleapis.com;
        proxy_pass_request_headers on;
        proxy_read_timeout 90s;
        proxy_connect_timeout 30s;
        proxy_send_timeout  60s;
    }

    location /ai-${NL_PROXY_TOKEN}/telegram {
        proxy_pass         http://127.0.0.1:${IMGPROXY_PORT}/?url=\$arg_url;
        proxy_http_version 1.0;
        proxy_read_timeout 120s;
        proxy_connect_timeout 30s;
        proxy_buffering    off;
        proxy_pass_request_headers off;
        proxy_set_header   Connection close;
    }

    location /ai-${NL_PROXY_TOKEN}/vk-api/ {
        proxy_pass         https://api.vk.com/;
        proxy_ssl_server_name on;
        proxy_set_header   Host api.vk.com;
        proxy_pass_request_headers on;
        proxy_read_timeout 90s;
        proxy_connect_timeout 30s;
        proxy_send_timeout  60s;
    }

    location /ai-${NL_PROXY_TOKEN}/imgproxy {
        proxy_pass         http://127.0.0.1:${IMGPROXY_PORT}/;
        proxy_http_version 1.0;
        proxy_read_timeout 120s;
        proxy_connect_timeout 30s;
        proxy_buffering    off;
        proxy_pass_request_headers off;
        proxy_set_header   Connection close;
    }

    location / {
        return 404;
    }
}

# ── Порт ${DEEPSEEK_PORT}: DeepSeek ──────────────────────────────────────────
# Клиент присылает X-Ai-Proxy-Token для авторизации.
# Сервер зажимает модель до flash и подставляет ключ локальным clamp-сервисом.
map \$http_x_ai_proxy_token \$deepseek_allowed {
    \"${NL_PROXY_TOKEN}\" 1;
    default               0;
}

server {
    listen ${DEEPSEEK_PORT};
    listen [::]:${DEEPSEEK_PORT};
    server_name _;

    location / {
        if (\$deepseek_allowed = 0) {
            return 401;
        }
        proxy_pass         http://127.0.0.1:${DEEPSEEK_CLAMP_PORT};
        proxy_pass_request_headers on;
        proxy_set_header   X-Ai-Proxy-Token \"\";
        proxy_set_header   Connection \"\";
        proxy_http_version 1.1;
        proxy_buffering    off;
        proxy_read_timeout 120s;
        proxy_connect_timeout 30s;
        proxy_send_timeout  60s;
    }
}"

echo "$NGINX_CONF" > /etc/nginx/conf.d/ai-proxy.conf

echo "▶  Проверяем конфиг nginx..."
nginx -t

echo "▶  Перезагружаем nginx (reload — без прерывания соединений)..."
systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || systemctl restart nginx

# Проверяем imgproxy
if ! systemctl is-active --quiet ai-imgproxy 2>/dev/null; then
    echo "⚠️  ai-imgproxy не запущен. Запустить: systemctl start ai-imgproxy"
fi

echo ""
echo "✅  AI-прокси применён."
