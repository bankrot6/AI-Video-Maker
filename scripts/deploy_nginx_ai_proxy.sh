#!/usr/bin/env bash
# ============================================================
# Деплой AI nginx-прокси на нидерландский сервер
#
# Режимы:
#   bash scripts/deploy_nginx_ai_proxy.sh
#       Обновить конфиг nginx (push deploy.sh + reload).
#       Используй для любых изменений маршрутов.
#
#   bash scripts/deploy_nginx_ai_proxy.sh --init
#       Первичная установка: imgproxy-сервис + secrets.env + deploy.sh.
#       Запускать один раз на новом сервере.
#
# Другие проекты (AI Video Maker, AI Video Maker) запускают свой
# scripts/deploy_nginx_ai_proxy.sh — он SSH-тригерит /opt/ai-proxy/deploy.sh.
#
# Требования (macOS): brew install hudochenkov/sshpass/sshpass
# ============================================================
set -euo pipefail

MODE="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${DEPLOY_ENV_FILE:-$SCRIPT_DIR/../.env}"
DEPLOY_SECRETS_FILE="${DEPLOY_SECRETS_FILE:-$SCRIPT_DIR/../.env.deploy}"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌  .env не найден: $ENV_FILE"
    exit 1
fi
# shellcheck source=/dev/null
set -a
source "$ENV_FILE"
[[ -f "$DEPLOY_SECRETS_FILE" ]] && source "$DEPLOY_SECRETS_FILE"
set +a

: "${NL_SERVER_HOST:?Заполни NL_SERVER_HOST в .env}"

NL_SERVER_SSH_PORT="${NL_SERVER_SSH_PORT:-22}"
NL_SERVER_SSH_USER="${NL_SERVER_SSH_USER:-root}"
NL_SERVER_SSH_PASSWORD="${NL_SERVER_SSH_PASSWORD:-}"
NL_SERVER_SSH_KEY_PATH="${NL_SERVER_SSH_KEY_PATH:-}"

# ─── SSH-обёртки ──────────────────────────────────────────────
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=20 -p $NL_SERVER_SSH_PORT"
[[ -n "$NL_SERVER_SSH_KEY_PATH" ]] && SSH_OPTS="$SSH_OPTS -i $NL_SERVER_SSH_KEY_PATH"
TARGET="$NL_SERVER_SSH_USER@$NL_SERVER_HOST"

check_sshpass() {
    if [[ -n "$NL_SERVER_SSH_PASSWORD" ]] && ! command -v sshpass &>/dev/null; then
        echo "❌  sshpass не найден. Установи: brew install hudochenkov/sshpass/sshpass"
        exit 1
    fi
}

ssh_exec() {
    if [[ -n "$NL_SERVER_SSH_PASSWORD" ]]; then
        sshpass -p "$NL_SERVER_SSH_PASSWORD" ssh $SSH_OPTS "$TARGET" "$@"
    else
        ssh $SSH_OPTS "$TARGET" "$@"
    fi
}

ssh_write_file() {
    local remote_path="$1"
    if [[ -n "$NL_SERVER_SSH_PASSWORD" ]]; then
        sshpass -p "$NL_SERVER_SSH_PASSWORD" ssh $SSH_OPTS "$TARGET" "cat > $remote_path"
    else
        ssh $SSH_OPTS "$TARGET" "cat > $remote_path"
    fi
}

scp_file() {
    local local_path="$1" remote_path="$2"
    if [[ -n "$NL_SERVER_SSH_PASSWORD" ]]; then
        sshpass -p "$NL_SERVER_SSH_PASSWORD" scp -P "$NL_SERVER_SSH_PORT" \
            -o StrictHostKeyChecking=no "$local_path" "$TARGET:$remote_path"
    else
        scp -P "$NL_SERVER_SSH_PORT" -o StrictHostKeyChecking=no \
            -i "$NL_SERVER_SSH_KEY_PATH" "$local_path" "$TARGET:$remote_path"
    fi
}

check_sshpass

echo "=================================================="
echo "  Деплой AI nginx-прокси"
echo "  Сервер : $TARGET:$NL_SERVER_SSH_PORT"
echo "  Режим  : ${MODE:-обновление конфига}"
echo "=================================================="
echo ""

# ─── --init: первичная установка ──────────────────────────────
if [[ "$MODE" == "--init" ]]; then
    echo "▶  Первичная инициализация /opt/ai-proxy/ ..."
    ssh_exec "mkdir -p /opt/ai-proxy && chmod 700 /opt/ai-proxy"

    # Создаём secrets.env на сервере (API-ключи для инжекции в nginx)
    echo "▶  Создаём /opt/ai-proxy/secrets.env ..."
    PIAPI_API_KEY_VAL="${PIAPI_API_KEY:-}"
    DEEPSEEK_API_KEY_VAL="${DEEPSEEK_API_KEY:-}"
    APIBOST_API_KEY_VAL="${API_BOST_API_KEY:-${APIBOST_API_KEY:-}}"
    NL_PROXY_TOKEN_VAL="${NL_PROXY_TOKEN:-}"
    PIAPI_PORT_VAL="${AI_PROXY_PIAPI_PORT:-8080}"
    DEEPSEEK_PORT_VAL="${AI_PROXY_DEEPSEEK_PORT:-8001}"

    SECRETS_CONTENT="# AI Proxy — серверные секреты
# Хранятся только на сервере, никуда не уходят.
# Обновить: запусти deploy_nginx_ai_proxy.sh --init повторно.
NL_PROXY_TOKEN=${NL_PROXY_TOKEN_VAL}
AI_PROXY_PIAPI_PORT=${PIAPI_PORT_VAL}
AI_PROXY_DEEPSEEK_PORT=${DEEPSEEK_PORT_VAL}
DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY_VAL}
API_BOST_API_KEY=${APIBOST_API_KEY_VAL}
PIAPI_API_KEY=${PIAPI_API_KEY_VAL}
"
    echo "$SECRETS_CONTENT" | ssh_write_file "/opt/ai-proxy/secrets.env"
    ssh_exec "chmod 600 /opt/ai-proxy/secrets.env"
    echo "   secrets.env сохранён (chmod 600)"

    # Разворачиваем Python image proxy
    echo "▶  Устанавливаем ai-imgproxy (Python, порт 8002)..."
    IMGPROXY_SCRIPT='#!/usr/bin/env python3
"""HTTP GET-прокси: GET /?url=<encoded> -> байты ответа."""
import sys, traceback, urllib.request, urllib.error
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import unquote, urlparse, parse_qs

_UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
       "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")

class _Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    _ALLOWED = ("http://", "https://")
    def do_GET(self):
        params = parse_qs(urlparse(self.path).query, keep_blank_values=True)
        url = unquote(params.get("url", [""])[0])
        if not url or not any(url.startswith(s) for s in self._ALLOWED):
            self._resp(400); return
        try:
            req = urllib.request.Request(url, headers={"User-Agent": _UA,
                "Accept": "application/json, image/*, */*;q=0.8"})
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read(); ct = r.headers.get("Content-Type","application/octet-stream")
                self.send_response(200)
                self.send_header("Content-Type", ct)
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Cache-Control", "public, max-age=300")
                self.end_headers(); self.wfile.write(data)
        except urllib.error.HTTPError as e:
            body = b""
            try: body = e.read()
            except Exception: pass
            self._resp(e.code, body)
        except Exception as exc:
            sys.stderr.write(f"[imgproxy] {exc}\n"); traceback.print_exc(file=sys.stderr)
            self._resp(502)
    def _resp(self, code, body=b""):
        self.send_response(code)
        if body: self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body: self.wfile.write(body)
    def log_message(self, fmt, *args):
        sys.stderr.write(f"[imgproxy] {self.address_string()} - {fmt % args}\n")

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8002
    server = HTTPServer(("127.0.0.1", port), _Handler)
    sys.stderr.write(f"[imgproxy] listening on 127.0.0.1:{port}\n")
    server.serve_forever()
'
    IMGPROXY_SERVICE="[Unit]
Description=AI Image Proxy
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/ai-imgproxy/server.py 8002
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ai-imgproxy
[Install]
WantedBy=multi-user.target"
    ssh_exec "mkdir -p /opt/ai-imgproxy"
    echo "$IMGPROXY_SCRIPT" | ssh_write_file "/opt/ai-imgproxy/server.py"
    ssh_exec "chmod +x /opt/ai-imgproxy/server.py"
    echo "$IMGPROXY_SERVICE" | ssh_write_file "/etc/systemd/system/ai-imgproxy.service"
    ssh_exec "systemctl daemon-reload && systemctl enable ai-imgproxy && systemctl restart ai-imgproxy"
    ssh_exec "sleep 1 && systemctl is-active ai-imgproxy && echo '   ai-imgproxy запущен' || echo '   ⚠️  ai-imgproxy не стартовал'"

    # Открываем порты
    PIAPI_PORT="${AI_PROXY_PIAPI_PORT:-8080}"
    DEEPSEEK_PORT="${AI_PROXY_DEEPSEEK_PORT:-8001}"
    echo "▶  Открываем порты $PIAPI_PORT и $DEEPSEEK_PORT в firewall..."
    set +e
    ssh_exec "
if command -v ufw &>/dev/null; then
    ufw allow ${PIAPI_PORT}/tcp 2>/dev/null || true
    ufw allow ${DEEPSEEK_PORT}/tcp 2>/dev/null || true
elif command -v iptables &>/dev/null; then
    iptables -I INPUT -p tcp --dport ${PIAPI_PORT} -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p tcp --dport ${DEEPSEEK_PORT} -j ACCEPT 2>/dev/null || true
fi
"
    set -e
    echo ""
fi

# ─── Обновляем Suno Voice callback receiver ────────────────────
echo "▶  Обновляем ai-suno-callback (Python, порт 8004)..."
SUNO_CALLBACK_SCRIPT='#!/usr/bin/env python3
import json
import os
import sys
import traceback
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse

DATA_DIR = "/opt/ai-suno-callbacks/data"

def _safe_task_id(value: str) -> str:
    return "".join(ch for ch in value if ch.isalnum() or ch in ("_", "-"))[:96]

def _read_json(handler):
    length = int(handler.headers.get("Content-Length", "0") or "0")
    raw = handler.rfile.read(length) if length > 0 else b"{}"
    return json.loads(raw.decode("utf-8") or "{}")

class _Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def do_POST(self):
        try:
            payload = _read_json(self)
            data = payload.get("data") or {}
            task_id = _safe_task_id(str(data.get("taskId") or ""))
            if not task_id:
                return self._json({"ok": False, "error": "missing_task_id"}, 400)
            os.makedirs(DATA_DIR, exist_ok=True)
            file_path = os.path.join(DATA_DIR, f"{task_id}.json")
            with open(file_path, "w", encoding="utf-8") as fh:
                json.dump(payload, fh, ensure_ascii=False)
            return self._json({"ok": True}, 200)
        except Exception as exc:
            sys.stderr.write(f"[suno-callback] POST error: {exc}\n")
            traceback.print_exc(file=sys.stderr)
            return self._json({"ok": False, "error": "internal_error"}, 500)

    def do_GET(self):
        try:
            parsed = urlparse(self.path)
            if parsed.path.rstrip("/") != "/query":
                return self._json({"ok": False, "error": "not_found"}, 404)
            params = parse_qs(parsed.query, keep_blank_values=True)
            task_id = _safe_task_id(params.get("taskId", [""])[0])
            if not task_id:
                return self._json({"ok": False, "error": "missing_task_id"}, 400)
            file_path = os.path.join(DATA_DIR, f"{task_id}.json")
            if not os.path.exists(file_path):
                return self._json({"ok": True, "found": False}, 200)
            with open(file_path, "r", encoding="utf-8") as fh:
                payload = json.load(fh)
            return self._json({"ok": True, "found": True, "payload": payload}, 200)
        except Exception as exc:
            sys.stderr.write(f"[suno-callback] GET error: {exc}\n")
            traceback.print_exc(file=sys.stderr)
            return self._json({"ok": False, "error": "internal_error"}, 500)

    def _json(self, body, status):
        raw = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def log_message(self, fmt, *args):
        sys.stderr.write(f"[suno-callback] {self.address_string()} - {fmt % args}\n")

if __name__ == "__main__":
    os.makedirs(DATA_DIR, exist_ok=True)
    server = HTTPServer(("127.0.0.1", 8004), _Handler)
    sys.stderr.write("[suno-callback] listening on 127.0.0.1:8004\n")
    server.serve_forever()
'
SUNO_CALLBACK_SERVICE="[Unit]
Description=Suno Voice Callback Receiver
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/ai-suno-callbacks/server.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ai-suno-callback
[Install]
WantedBy=multi-user.target"
ssh_exec "mkdir -p /opt/ai-suno-callbacks/data"
echo "$SUNO_CALLBACK_SCRIPT" | ssh_write_file "/opt/ai-suno-callbacks/server.py"
ssh_exec "chmod +x /opt/ai-suno-callbacks/server.py"
echo "$SUNO_CALLBACK_SERVICE" | ssh_write_file "/etc/systemd/system/ai-suno-callback.service"
ssh_exec "systemctl daemon-reload && systemctl enable ai-suno-callback && systemctl restart ai-suno-callback"
ssh_exec "sleep 1 && systemctl is-active ai-suno-callback && echo '   ai-suno-callback запущен' || echo '   ⚠️  ai-suno-callback не стартовал'"

# ─── Обновляем deploy.sh и применяем конфиг ───────────────────
SERVER_DEPLOY_SH="$SCRIPT_DIR/server/ai-proxy-deploy.sh"
if [[ ! -f "$SERVER_DEPLOY_SH" ]]; then
    echo "❌  Не найден: $SERVER_DEPLOY_SH"
    exit 1
fi

APIBOST_RELAY_PY="$SCRIPT_DIR/server/apibost-relay.py"
if [[ ! -f "$APIBOST_RELAY_PY" ]]; then
    echo "❌  Не найден: $APIBOST_RELAY_PY"
    exit 1
fi

echo "▶  Загружаем /opt/ai-proxy/deploy.sh на сервер..."
ssh_exec "mkdir -p /opt/ai-proxy /opt/ai-apibost-relay"
scp_file "$SERVER_DEPLOY_SH" "/opt/ai-proxy/deploy.sh"
ssh_exec "chmod 755 /opt/ai-proxy/deploy.sh"

echo "▶  Загружаем ai-apibost-relay на сервер..."
scp_file "$APIBOST_RELAY_PY" "/opt/ai-apibost-relay/server.py"
ssh_exec "chmod 755 /opt/ai-apibost-relay/server.py"

echo "▶  Запускаем deploy.sh на сервере..."
ssh_exec "bash /opt/ai-proxy/deploy.sh"

echo ""
echo "✅  Готово! Конфиг применён."
echo ""
echo "Следующие деплои из любого проекта:"
echo "  bash scripts/deploy_nginx_ai_proxy.sh"
