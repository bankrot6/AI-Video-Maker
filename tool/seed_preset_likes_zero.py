#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import random
import sys
import time
from pathlib import Path
from typing import Any, Dict

_tool_dir = Path(__file__).resolve().parent
if str(_tool_dir) not in sys.path:
    sys.path.insert(0, str(_tool_dir))

import seed_preset_likes as spl  # noqa: E402


def current_like_count(fields: Dict[str, Any]) -> int:
    raw = fields.get("likesCount", {})
    if "integerValue" in raw:
        try:
            return int(raw["integerValue"])
        except ValueError:
            pass
    return len(spl._string_array_from_fields(fields, "likedBy"))


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Синтетические лайки только у пресетов с 0 лайков (Firestore)"
    )
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

    sa = spl.load_service_account()
    project_id = sa["project_id"]
    print("═══════════════════════════════════════════════════")
    print("  SEED PRESET LIKES (только 0 лайков)  Firestore")
    print("═══════════════════════════════════════════════════")
    print(f"📦 Project: {project_id}")
    print(f"📂 Collection: {args.collection}")
    print(f"🎲 Лайков на документ: {args.min_likes}…{args.max_likes} (случайно)")
    print("🎯 Только документы с 0 лайков (likesCount / likedBy)")
    if args.dry_run:
        print("🔸 Режим DRY-RUN — записи не будет\n")
    else:
        print()

    token = spl.get_access_token(sa)
    print("✅ Токен получен, читаю документы…\n")

    docs = spl.list_all_presets(token, project_id, args.collection)
    if not docs:
        print("❌ Документы не найдены")
        sys.exit(1)

    zero_docs = [(did, f) for did, f in docs if current_like_count(f) == 0]
    skipped = len(docs) - len(zero_docs)
    print(f"📋 Документов всего: {len(docs)}  с 0 лайков: {len(zero_docs)}\n")

    ok, err = 0, 0
    nz = len(zero_docs)
    for i, (doc_id, fields) in enumerate(zero_docs, 1):
        target = random.randint(args.min_likes, args.max_likes)
        try:
            new_liked, note = spl.compute_liked_by(fields, target)
            old = spl._string_array_from_fields(fields, "likedBy")
            if new_liked == old:
                print(f"[{i}/{nz}] {doc_id} — без изменений ({note})")
                ok += 1
                continue
            print(f"[{i}/{nz}] {doc_id} — {note} → всего {len(new_liked)}")
            if not args.dry_run:
                spl.patch_preset(
                    token,
                    project_id,
                    args.collection,
                    doc_id,
                    spl.build_patch_fields(new_liked),
                )
                time.sleep(0.05)
            ok += 1
        except Exception as e:
            print(f"[{i}/{nz}] {doc_id} ❌ {e}")
            err += 1

    print("\n═══════════════════════════════════════════════════")
    print(f"✅ Обработано (из 0-лайковых): {ok}  ⏭ Пропущено (уже с лайками): {skipped}  ❌ Ошибок: {err}")
    print("═══════════════════════════════════════════════════")


if __name__ == "__main__":
    main()
