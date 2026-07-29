#!/usr/bin/env python3
"""Удаление среди N последних по createdAt пресетов тех, что по title/prompt похожи на Чебурашку или Человека-паука."""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import jwt
import requests

SA_PATHS = [
    Path(__file__).resolve().parent.parent / "firebase-service-account.json",
    Path(__file__).resolve().parent / "firebase-service-account.json",
]


def load_service_account() -> dict:
    for p in SA_PATHS:
        if p.exists():
            with open(p, encoding="utf-8") as f:
                return json.load(f)
    print("❌ Нет firebase-service-account.json (корень или tool/)")
    sys.exit(1)


def get_access_token(sa: dict) -> str:
    now = int(time.time())
    payload = {
        "iss": sa["client_email"],
        "sub": sa["client_email"],
        "aud": sa["token_uri"],
        "iat": now,
        "exp": now + 3600,
        "scope": "https://www.googleapis.com/auth/datastore",
    }
    signed = jwt.encode(payload, sa["private_key"], algorithm="RS256")
    resp = requests.post(
        sa["token_uri"],
        data={
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": signed,
        },
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()["access_token"]


def field_string(fields: dict, key: str) -> str:
    f = fields.get(key, {})
    if "stringValue" in f:
        return f["stringValue"] or ""
    if "timestampValue" in f:
        return f["timestampValue"] or ""
    return ""


def list_all_presets(token: str, project_id: str) -> List[Tuple[str, str, dict]]:
    out: List[Tuple[str, str, dict]] = []
    page_token: Optional[str] = None
    while True:
        url = (
            f"https://firestore.googleapis.com/v1/projects/{project_id}"
            f"/databases/(default)/documents/presets?pageSize=300"
        )
        if page_token:
            url += f"&pageToken={page_token}"
        resp = requests.get(
            url, headers={"Authorization": f"Bearer {token}"}, timeout=60
        )
        resp.raise_for_status()
        data = resp.json()
        for doc in data.get("documents", []):
            name = doc.get("name", "")
            doc_id = name.rsplit("/", 1)[-1]
            fields = doc.get("fields") or {}
            out.append((doc_id, name, fields))
        page_token = data.get("nextPageToken")
        if not page_token:
            break
        time.sleep(0.12)
    return out


def created_sort_key(fields: dict) -> str:
    return field_string(fields, "createdAt") or "1970-01-01"


def matches_cheburashka(text: str) -> bool:
    t = text.lower()
    return "чебурашк" in t or "cheburashka" in t


def matches_spider(text: str) -> bool:
    t = text.lower()
    if "чебурашк" in t or "cheburashka" in t:
        return False
    return (
        "человек-паук" in t
        or "человек паук" in t
        or "spider-man" in t
        or "spiderman" in t
        or "spider man" in t
        or ("паук" in t and "человек" in t)
    )


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--recent", type=int, default=5, help="Сколько последних по дате пресетов смотреть")
    ap.add_argument(
        "--apply",
        action="store_true",
        help="Реально удалить (без флага только список)",
    )
    args = ap.parse_args()

    sa = load_service_account()
    project_id = sa["project_id"]
    token = get_access_token(sa)

    rows = list_all_presets(token, project_id)
    enriched: List[Tuple[str, str, dict, str]] = []
    for doc_id, name, fields in rows:
        title = field_string(fields, "title")
        prompt = field_string(fields, "prompt")
        created = created_sort_key(fields)
        enriched.append((doc_id, name, fields, created))

    enriched.sort(key=lambda x: x[3], reverse=True)
    window = enriched[: max(1, args.recent)]

    to_delete: List[Dict[str, Any]] = []
    got_che = False
    got_spider = False
    for doc_id, name, fields, created in window:
        title = field_string(fields, "title")
        prompt = field_string(fields, "prompt")
        blob = f"{title} {prompt}"
        reason: Optional[str] = None
        if matches_cheburashka(blob) and not got_che:
            reason = "чебурашка"
            got_che = True
        elif matches_spider(blob) and not got_spider:
            reason = "человек-паук / spider-man"
            got_spider = True
        if reason:
            to_delete.append(
                {
                    "doc_id": doc_id,
                    "name": name,
                    "reason": reason,
                    "title": title,
                    "createdAt": created,
                }
            )
        if got_che and got_spider:
            break

    print(f"Проект: {project_id}")
    print(f"Всего пресетов: {len(rows)}")
    print(f"Окно «последние {args.recent}» по createdAt: {len(window)} документов\n")

    if not to_delete:
        print("Ни один из последних пресетов не совпал с Чебурашкой / Человеком-пауком.")
        print("Проверьте title/prompt или увеличьте --recent.")
        for doc_id, _, fields, c in window[:10]:
            print(f"  - {doc_id} | {c[:19]} | {field_string(fields, 'title')[:60]}")
        return

    for item in to_delete:
        print(
            f"→ {'Удалить' if args.apply else 'К удалению'}: {item['doc_id']} ({item['reason']})"
        )
        ca = (item["createdAt"] or "")[:22]
        print(f"   createdAt: {ca}… | {(item['title'] or '')[:100]}")

    if not args.apply:
        print("\n🔸 DRY-RUN. Запустите с --apply для удаления.")
        return

    token = get_access_token(sa)
    for item in to_delete:
        doc_id = item["doc_id"]
        name = item["name"]
        reason = item["reason"]
        del_url = f"https://firestore.googleapis.com/v1/{name}"
        r = requests.delete(
            del_url, headers={"Authorization": f"Bearer {token}"}, timeout=30
        )
        if r.status_code in (200, 204):
            print(f"✅ Удалён {doc_id} ({reason})")
        else:
            print(f"❌ {doc_id}: HTTP {r.status_code} {r.text[:200]}")


if __name__ == "__main__":
    main()
