#!/usr/bin/env bash
# Одноразовый ребрендинг клона Repiin в AI Video Maker.
# Файлы сервисных аккаунтов пропускаем: их выдаёт новый Firebase-проект.
set -euo pipefail

cd "$(dirname "$0")/.."

count=0
while IFS= read -r file; do
  perl -0777 -pi -e '
    s/com\.repiin\.bankr0t/com.aivideomaker.app/g;
    s/com\.example\.repiin/com.aivideomaker/g;
    s/com\.repiin\.app/com.aivideomaker.app/g;
    s/com\.repiin\.subscription/com.aivideomaker.subscription/g;
    s{app\.repiin/}{app.aivideomaker/}g;
    s/repiin-app/aivideomaker-app/g;
    s/repiin-admin/aivideomaker-admin/g;
    s{repiin://}{aivideomaker://}g;
    s/repiin\.app/aivideomaker.app/g;
    s/repiin\./aivideomaker./g;
    s/repiin_/aivideomaker_/g;
    s{Repiin/}{AIVideoMaker/}g;
    s/Repiin/AI Video Maker/g;
    s/repiin/aivideomaker/g;
    s/РепИИн/AI Video Maker/g;
    s/Friendogram/AI Video Maker/g;
    s/friendogram/aivideomaker/g;
    s/AIplate/AI Video Maker/g;
    s/aiplate/aivideomaker/g;
  ' "$file"
  count=$((count + 1))
done < <(
  rg -l -i 'repiin|friendogram|aiplate' \
    --glob '!build/**' \
    --glob '!node_modules/**' \
    --glob '!.git/**' \
    --glob '!pubspec.lock' \
    --glob '!firebase-service-account.json' \
    --glob '!functions/service-account.json' \
    --glob '!scripts/rebrand_to_aivideomaker.sh' \
    .
)

# Kotlin-пакет задан ещё и путём в дереве исходников.
OLD_KOTLIN=android/app/src/main/kotlin/com/repiin/bankr0t
NEW_KOTLIN=android/app/src/main/kotlin/com/aivideomaker/app
if [[ -d $OLD_KOTLIN ]]; then
  mkdir -p "$(dirname "$NEW_KOTLIN")"
  mv "$OLD_KOTLIN" "$NEW_KOTLIN"
  rmdir android/app/src/main/kotlin/com/repiin 2>/dev/null || true
fi

echo "rebrand finished: $count files processed"
