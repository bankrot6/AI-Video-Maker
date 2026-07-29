#!/usr/bin/env python3
import http.client
import json
import os
import re
import sys
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

LISTEN_HOST = os.environ.get("APIBOST_RELAY_BIND", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("APIBOST_RELAY_PORT", "8006"))
UPSTREAM_HOST = "apibost.com"
API_KEY = os.environ["API_BOST_API_KEY"]
UPSTREAM_TIMEOUT_SEC = int(os.environ.get("APIBOST_RELAY_TIMEOUT_SEC", "420"))

FLASH_25_MODEL = "gemini-2.5-flash-image"
# GA-слаг 3.1 у ApiBost переведён на token-биллинг и отвечает ошибками,
# рабочий вариант с оплатой за запрос — preview.
FLASH_31_PREVIEW_MODEL = "gemini-3.1-flash-image-preview"
MODEL_PATH_RE = re.compile(r"^(/v1beta/models/)([^/:]+)(.*)$")

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
    "authorization",
}


def extract_model(path):
    match = MODEL_PATH_RE.match(path)
    if not match:
        return None, path
    return match.group(2), path


def replace_model(path, new_model):
    match = MODEL_PATH_RE.match(path)
    if not match:
        return path
    return f"{match.group(1)}{new_model}{match.group(3)}"


def is_31_flash_image(model):
    return "3.1-flash-image" in str(model or "").lower()


def is_31_preview(model):
    normalized = str(model or "").lower()
    return "3.1-flash-image-preview" in normalized


def should_fallback_to_25(status, body_text):
    if status in {400, 404, 503}:
        return True
    if status >= 500:
        return True
    msg = str(body_text or "").lower()
    return (
        "not been priced" in msg
        or "价格尚未" in msg
        or "no available channel" in msg
        or "openai_error" in msg
    )


def relay_plan(path):
    model, _ = extract_model(path)
    if not model:
        return path, None, None

    # Старые сборки в сторах просят GA-слаг — переводим их на рабочий preview.
    if is_31_flash_image(model) and not is_31_preview(model):
        preview_path = replace_model(path, FLASH_31_PREVIEW_MODEL)
        return preview_path, "31-fallback", "31-ga->preview"

    if is_31_preview(model):
        return path, "31-fallback", None

    return path, None, None


def call_upstream(method, path, body, incoming_headers):
    headers = {
        "Host": UPSTREAM_HOST,
        "Authorization": f"Bearer {API_KEY}",
        "Accept-Encoding": "identity",
    }
    for key, value in incoming_headers.items():
        lower = key.lower()
        if lower in HOP_HEADERS:
            continue
        headers[key] = value

    conn = http.client.HTTPSConnection(UPSTREAM_HOST, timeout=UPSTREAM_TIMEOUT_SEC)
    try:
        conn.request(method, path, body=body, headers=headers)
        response = conn.getresponse()
        data = response.read()
        return response.status, response.reason, response.getheaders(), data
    finally:
        conn.close()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send_upstream(self, status, reason, headers, body, extra_headers=None):
        self.send_response(status, reason or "")
        skip = {"transfer-encoding", "connection"}
        relay_meta = {"x-apibost-actual-model", "x-apibost-requested-model"}
        if extra_headers:
            skip |= {k.lower() for k in extra_headers}
        for key, value in headers:
            lower = key.lower()
            if lower in skip or lower in relay_meta:
                continue
            self.send_header(key, value)
        if extra_headers:
            for key, value in extra_headers.items():
                self.send_header(key, value)
        if body is not None:
            if not any(k.lower() == "content-length" for k, _ in headers):
                if not extra_headers or not any(
                    k.lower() == "content-length" for k in extra_headers
                ):
                    self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _read_body(self):
        length = int(self.headers.get("Content-Length", "0") or "0")
        return self.rfile.read(length) if length > 0 else b""

    def _proxy(self):
        split = urlsplit(self.path)
        path = split.path
        if split.query:
            path = f"{path}?{split.query}"

        if path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            payload = json.dumps({"ok": True, "service": "apibost-relay"}).encode("utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return

        body = self._read_body()
        incoming_headers = dict(self.headers.items())
        primary_path, mode, rewrite_note = relay_plan(path)
        requested_model, _ = extract_model(path)

        try:
            if mode == "31-fallback":
                if rewrite_note:
                    sys.stderr.write(
                        f"[apibost-relay] rewrite {rewrite_note} "
                        f"path={path} -> {primary_path}\n"
                    )
                status, reason, headers, data = call_upstream(
                    self.command, primary_path, body, incoming_headers
                )
                body_text = data.decode("utf-8", errors="replace")
                primary_model, _ = extract_model(primary_path)
                if status < 400 or not should_fallback_to_25(status, body_text):
                    if primary_model:
                        sys.stderr.write(
                            f"[apibost-relay] фактическая модель={primary_model} "
                            f"(запрошена={requested_model or primary_model})\n"
                        )
                    self._send_upstream(
                        status,
                        reason,
                        headers,
                        data,
                        extra_headers={
                            "X-Apibost-Actual-Model": primary_model or "",
                            "X-Apibost-Requested-Model": requested_model or primary_model or "",
                        },
                    )
                    return

                fallback_path = replace_model(primary_path, FLASH_25_MODEL)
                sys.stderr.write(
                    f"[apibost-relay] relay 3.1->2.5 HTTP {status} "
                    f"path={primary_path}\n"
                )
                status, reason, headers, data = call_upstream(
                    self.command, fallback_path, body, incoming_headers
                )
                sys.stderr.write(
                    f"[apibost-relay] фактическая модель={FLASH_25_MODEL} "
                    f"(запрошена={requested_model or primary_model})\n"
                )
                self._send_upstream(
                    status,
                    reason,
                    headers,
                    data,
                    extra_headers={
                        "X-Apibost-Actual-Model": FLASH_25_MODEL,
                        "X-Apibost-Requested-Model": requested_model or primary_model or "",
                    },
                )
                return

            status, reason, headers, data = call_upstream(
                self.command, path, body, incoming_headers
            )
            actual_model, _ = extract_model(path)
            extra_headers = None
            if actual_model:
                extra_headers = {
                    "X-Apibost-Actual-Model": actual_model,
                    "X-Apibost-Requested-Model": actual_model,
                }
            self._send_upstream(status, reason, headers, data, extra_headers=extra_headers)
        except Exception as exc:
            sys.stderr.write(f"[apibost-relay] upstream error: {exc}\n")
            traceback.print_exc(file=sys.stderr)
            payload = json.dumps(
                {"error": {"message": f"apibost relay upstream failure: {exc}"}}
            ).encode("utf-8")
            self.send_response(502)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

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

    def log_message(self, fmt, *args):
        sys.stderr.write(f"[apibost-relay] {self.address_string()} - {fmt % args}\n")


if __name__ == "__main__":
    if not API_KEY:
        sys.stderr.write("[apibost-relay] API_BOST_API_KEY is required\n")
        sys.exit(1)
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    sys.stderr.write(
        f"[apibost-relay] listening on {LISTEN_HOST}:{LISTEN_PORT}, "
        f"upstream=https://{UPSTREAM_HOST}\n"
    )
    server.serve_forever()
