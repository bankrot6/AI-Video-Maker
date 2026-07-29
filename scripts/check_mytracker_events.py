#!/usr/bin/env python3
"""Проверка доставки кастомных событий в MyTracker через Raw Export API.

Скрипт создаёт запрос на выгрузку сырых событий (event=customEvents),
дожидается готовности, скачивает CSV (gzip) и печатает сводку:
сколько событий каждого типа пришло за указанный период.

Креды берутся из переменных окружения (секреты не хардкодятся):
  MYTRACKER_API_USER_ID  — API User ID из профиля MyTracker
  MYTRACKER_API_SECRET   — Secret key из профиля MyTracker

Пример:
  MYTRACKER_API_USER_ID=77658 MYTRACKER_API_SECRET=xxxx \
    python3 scripts/check_mytracker_events.py \
      --events trial_started subscription_purchase subscription_start \
      --date-from 2026-06-24 --date-to 2026-06-24
"""

import argparse
import base64
import csv
import gzip
import hashlib
import hmac
import io
import json
import os
import sys
import time
import urllib.parse
import urllib.request

BASE_HOST = "https://tracker.my.com"
CREATE_PATH = "/api/raw/v1/export/create.json"
GET_PATH = "/api/raw/v1/export/get.json"

# MyTracker требует percent-encoding по RFC3986 (без исключений для ~ и т.п.)
_SAFE = "-._~"


def _quote(value: str) -> str:
    return urllib.parse.quote(str(value), safe=_SAFE)


def _build_query(params: list[tuple[str, str]]) -> str:
    # Сохраняем порядок и поддерживаем повторяющиеся ключи (eventName[]).
    return "&".join(f"{_quote(k)}={_quote(v)}" for k, v in params)


def _sign(method: str, url: str, secret: str, body: str = "") -> str:
    baseline = "&".join([
        method.upper(),
        _quote(url),
        _quote(body),
    ])
    digest = hmac.new(secret.encode("utf-8"), baseline.encode("utf-8"),
                      hashlib.sha1).digest()
    return base64.b64encode(digest).decode("utf-8")


def _request(method: str, url: str, user_id: str, secret: str) -> dict:
    signature = _sign(method, url, secret)
    req = urllib.request.Request(url, method=method)
    req.add_header("Authorization", f"AuthHMAC {user_id}:{signature}")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        raise SystemExit(
            f"HTTP {e.code} при запросе {method} {url}\n{detail}")
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        raise SystemExit(f"Не удалось распарсить ответ:\n{raw}")


_PAYMENT_EVENTS = {"payments", "testPayments", "trialPayments"}

_SELECTORS = {
    "customEvents":
        "SDKKey,idApp,eventName,eventValue,dtEvent,tsEvent,idAppTitle,idCountryISOAlpha2",
    "payments":
        "SDKKey,dtEvent,tsEvent,sumRub,sumSrc,idCurrencyCode,idProduct,"
        "idTransaction,isVerified,idAppTitle",
}


def _selectors_for(event: str) -> str:
    if event in _PAYMENT_EVENTS:
        return _SELECTORS["payments"]
    return _SELECTORS["customEvents"]


def create_export(user_id: str, secret: str, events: list[str],
                  date_from: str, date_to: str, timezone: str,
                  filter_by_name: bool = True,
                  event_type: str = "customEvents") -> str:
    params: list[tuple[str, str]] = [
        ("event", event_type),
        ("selectors", _selectors_for(event_type)),
        ("dateFrom", date_from),
        ("dateTo", date_to),
        ("timezone", timezone),
    ]
    # Фильтр по имени применим только к кастомным событиям.
    if filter_by_name and event_type == "customEvents":
        for name in events:
            params.append(("eventName[]", name))

    url = f"{BASE_HOST}{CREATE_PATH}?{_build_query(params)}"
    data = _request("GET", url, user_id, secret)
    id_raw = (data.get("data") or {}).get("idRawExport")
    if not id_raw:
        raise SystemExit(f"Не получили idRawExport: {json.dumps(data, ensure_ascii=False)}")
    print(f"[create] idRawExport={id_raw}")
    return str(id_raw)


def wait_export(user_id: str, secret: str, id_raw: str,
                attempts: int, delay_sec: int) -> list[str]:
    params = [("idRawExport", id_raw)]
    url = f"{BASE_HOST}{GET_PATH}?{_build_query(params)}"

    for attempt in range(1, attempts + 1):
        data = _request("GET", url, user_id, secret)
        payload = data.get("data") or {}
        status = str(payload.get("status", ""))
        print(f"[get {attempt}/{attempts}] status={status!r}")

        if status.lower().startswith("success"):
            files = payload.get("files") or []
            links = [f["link"] for f in files if f.get("link")]
            if not links:
                print("Статус Success, но файлов нет — событий за период не найдено.")
            return links

        if status.lower() in {"error", "canceled", "cancelled"}:
            raise SystemExit(f"Выгрузка завершилась со статусом: {status}")

        time.sleep(delay_sec)

    raise SystemExit("Таймаут ожидания готовности выгрузки. Повтори позже.")


def download_and_summarize(links: list[str], events: list[str],
                           event_type: str = "customEvents") -> None:
    if not links:
        print("\nИТОГО: 0 событий за период.")
        return

    is_payments = event_type in _PAYMENT_EVENTS
    counts: dict[str, int] = {} if is_payments else {n: 0 for n in events}
    total = 0
    sum_rub = 0.0
    sample_rows: list[dict] = []

    for link in links:
        with urllib.request.urlopen(link, timeout=120) as resp:
            blob = resp.read()
        text = gzip.decompress(blob).decode("utf-8", errors="replace")
        reader = csv.DictReader(io.StringIO(text))
        for row in reader:
            total += 1
            if is_payments:
                try:
                    sum_rub += float(row.get("sumRub") or 0)
                except ValueError:
                    pass
            else:
                name = row.get("eventName") or row.get("event_name") or "?"
                counts[name] = counts.get(name, 0) + 1
            if len(sample_rows) < 5:
                sample_rows.append(row)

    print(f"\n===== СВОДКА ({event_type}) =====")
    if is_payments:
        print(f"  Платежей: {total}")
        print(f"  Сумма (RUB): {sum_rub:.2f}")
        keys = ("dtEvent", "tsEvent", "sumRub", "sumSrc", "idCurrencyCode",
                "idProduct", "idTransaction", "isVerified", "idAppTitle")
    else:
        for name in sorted(counts):
            print(f"  {name}: {counts[name]}")
        print(f"  ВСЕГО строк: {total}")
        keys = ("eventName", "idApp", "eventValue", "dtEvent", "tsEvent",
                "idAppTitle", "idCountryISOAlpha2")

    if sample_rows:
        print("\nПримеры (до 5 строк):")
        for r in sample_rows:
            print("  ", {k: r.get(k) for k in keys})


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Проверка доставки кастомных событий в MyTracker")
    parser.add_argument("--events", nargs="+", default=[
        "trial_started", "subscription_start", "subscription_purchase",
        "credits_purchase", "app_install", "paywall_open",
    ], help="Список имён кастомных событий для проверки")
    parser.add_argument("--date-from", required=True, help="YYYY-MM-DD")
    parser.add_argument("--date-to", required=True, help="YYYY-MM-DD")
    parser.add_argument("--timezone", default="Europe/Moscow")
    parser.add_argument("--attempts", type=int, default=30)
    parser.add_argument("--delay", type=int, default=10,
                        help="Пауза между опросами статуса, сек")
    parser.add_argument("--all", action="store_true",
                        help="Выгрузить все кастомные события без фильтра по имени")
    parser.add_argument("--event-type", default="customEvents",
                        choices=["customEvents", "payments", "testPayments",
                                 "trialPayments"],
                        help="Тип события для выгрузки (по умолчанию customEvents)")
    args = parser.parse_args()

    user_id = os.environ.get("MYTRACKER_API_USER_ID", "").strip()
    secret = os.environ.get("MYTRACKER_API_SECRET", "").strip()
    if not user_id or not secret:
        raise SystemExit(
            "Нужны переменные окружения MYTRACKER_API_USER_ID и MYTRACKER_API_SECRET.\n"
            "Возьми их в профиле MyTracker (раздел доступа к API).")

    id_raw = create_export(user_id, secret, args.events,
                           args.date_from, args.date_to, args.timezone,
                           filter_by_name=not args.all,
                           event_type=args.event_type)
    links = wait_export(user_id, secret, id_raw, args.attempts, args.delay)
    download_and_summarize(links, args.events, event_type=args.event_type)


if __name__ == "__main__":
    main()
