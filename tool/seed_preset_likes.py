#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Синтетические лайки для витрины: у каждого пресета итоговое число лайков
случайно в диапазоне [min, max] (по умолчанию 5–50).

Реальные ID (не начинающиеся с seed_) не удаляются. ID вида seed_* от прошлых
запусков удаляются и при необходимости создаются заново.

Требуется Service Account: firebase-service-account.json или tool/firebase-service-account.json

Запуск:
    python3 tool/seed_preset_likes.py
    python3 tool/seed_preset_likes.py --dry-run
    python3 tool/seed_preset_likes.py --min 10 --max 40
"""

from __future__ import annotations

import argparse
import json
import random
import sys
import time
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    import requests
except ImportError:
    print("❌ pip3 install requests")
    sys.exit(1)

try:
    import jwt
except ImportError:
    print("❌ pip3 install PyJWT cryptography")
    sys.exit(1)

SA_PATHS = [
    Path("firebase-service-account.json"),
    Path("tool/firebase-service-account.json"),
]
SEED_PREFIX = "seed_"


def load_service_account() -> dict:
    for p in SA_PATHS:
        if p.exists():
            with open(p, encoding="utf-8") as f:
                return json.load(f)
    print("❌ Нет ключа Service Account (firebase-service-account.json)")
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


def _string_array_from_fields(fields: dict, key: str) -> List[str]:
    raw = fields.get(key, {})
    arr = raw.get("arrayValue", {}).get("values", [])
    out: List[str] = []
    for item in arr:
        s = item.get("stringValue")
        if isinstance(s, str) and s:
            out.append(s)
    return out


def doc_id_from_name(name: str) -> str:
    return name.rsplit("/", 1)[-1]


def list_all_presets(token: str, project_id: str, collection: str) -> List[Tuple[str, dict]]:
    base = (
        f"https://firestore.googleapis.com/v1/projects/{project_id}"
        f"/databases/(default)/documents/{collection}"
    )
    headers = {"Authorization": f"Bearer {token}"}
    out: List[Tuple[str, dict]] = []
    page_token: Optional[str] = None

    while True:
        params: Dict[str, Any] = {"pageSize": 300}
        if page_token:
            params["pageToken"] = page_token
        resp = requests.get(base, headers=headers, params=params, timeout=60)
        resp.raise_for_status()
        data = resp.json()
        for doc in data.get("documents", []):
            name = doc.get("name", "")
            did = doc_id_from_name(name)
            fields = doc.get("fields") or {}
            out.append((did, fields))
        page_token = data.get("nextPageToken")
        if not page_token:
            break
        time.sleep(0.15)

    return out


def build_patch_fields(liked_by: List[str]) -> dict:
    return {
        "likedBy": {
            "arrayValue": {
                "values": [{"stringValue": x} for x in liked_by],
            }
        },
        "likesCount": {"integerValue": str(len(liked_by))},
    }


def patch_preset(
    token: str,
    project_id: str,
    collection: str,
    doc_id: str,
    fields_payload: dict,
) -> None:
    url = (
        f"https://firestore.googleapis.com/v1/projects/{project_id}"
        f"/databases/(default)/documents/{collection}/{doc_id}"
    )
    params = [
        ("updateMask.fieldPaths", "likedBy"),
        ("updateMask.fieldPaths", "likesCount"),
    ]
    resp = requests.patch(
        url,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        params=params,
        json={"fields": fields_payload},
        timeout=30,
    )
    resp.raise_for_status()


def compute_liked_by(
    fields: dict,
    target: int,
) -> Tuple[List[str], str]:
    current = _string_array_from_fields(fields, "likedBy")
    real = [x for x in current if not x.startswith(SEED_PREFIX)]

    if len(real) >= target:
        new_list = list(real)
        note = f"реальных {len(real)} ≥ {target}, только сняты seed_*"
    else:
        need = target - len(real)
        seeds = [f"{SEED_PREFIX}{uuid.uuid4().hex}" for _ in range(need)]
        new_list = real + seeds
        note = f"цель {target}: {len(real)} реальных + {need} seed_*"

    return new_list, note


def main() -> None:
    ap = argparse.ArgumentParser(description="Проставить синтетические лайки пресетам в Firestore")
    ap.add_argument("--min", dest="min_likes", type=int, default=5, help="Минимум лайков на пресет")
    ap.add_argument("--max", dest="max_likes", type=int, default=50, help="Максимум лайков на пресет")
    ap.add_argument("--collection", default="presets", help="Имя коллекции")
    ap.add_argument("--dry-run", action="store_true", help="Только вывод, без записи")
    ap.add_argument("--seed", type=int, default=None, help="Фиксированный random seed")
    args = ap.parse_args()

    if args.min_likes < 0 or args.max_likes < args.min_likes:
        print("❌ Некорректный диапазон min/max")
        sys.exit(1)

    if args.seed is not None:
        random.seed(args.seed)

    sa = load_service_account()
    project_id = sa["project_id"]
    print("═══════════════════════════════════════════════════")
    print("  SEED PRESET LIKES  Firestore")
    print("═══════════════════════════════════════════════════")
    print(f"📦 Project: {project_id}")
    print(f"📂 Collection: {args.collection}")
    print(f"🎲 Лайков на документ: {args.min_likes}…{args.max_likes} (случайно)")
    if args.dry_run:
        print("🔸 Режим DRY-RUN — записи не будет\n")
    else:
        print()

    token = get_access_token(sa)
    print("✅ Токен получен, читаю документы…\n")

    docs = list_all_presets(token, project_id, args.collection)
    if not docs:
        print("❌ Документы не найдены")
        sys.exit(1)

    print(f"📋 Документов: {len(docs)}\n")

    ok, err = 0, 0
    for i, (doc_id, fields) in enumerate(docs, 1):
        target = random.randint(args.min_likes, args.max_likes)
        try:
            new_liked, note = compute_liked_by(fields, target)
            old = _string_array_from_fields(fields, "likedBy")
            if new_liked == old:
                print(f"[{i}/{len(docs)}] {doc_id} — без изменений ({note})")
                ok += 1
                continue
            print(f"[{i}/{len(docs)}] {doc_id} — {note} → всего {len(new_liked)}")
            if not args.dry_run:
                patch_preset(
                    token,
                    project_id,
                    args.collection,
                    doc_id,
                    build_patch_fields(new_liked),
                )
                time.sleep(0.05)
            ok += 1
        except Exception as e:
            print(f"[{i}/{len(docs)}] {doc_id} ❌ {e}")
            err += 1

    print("\n═══════════════════════════════════════════════════")
    print(f"✅ Обработано: {ok}  ❌ Ошибок: {err}")
    print("═══════════════════════════════════════════════════")


if __name__ == "__main__":
    main()
