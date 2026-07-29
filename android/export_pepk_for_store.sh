#!/usr/bin/env bash
# Экспорт ключа для RuStore / Play (PEPK). storeFile в key.properties — как в Gradle (от android/app/).
#
# Автоматика:
#   1) Подхватывает android/.signing_env (export STORE_PASSWORD / KEY_PASSWORD), если есть.
#   2) Если пароли не заданы — читает storePassword и keyPassword из android/key.properties.
#   3) Ключ шифрования RuStore: переменная PEPK_ENCRYPTION_KEY или первая строка android/.pepk_encryption_key
#
# Запуск: из корня репозитория
#   chmod +x android/export_pepk_for_store.sh
#   ./android/export_pepk_for_store.sh
#   ./android/export_pepk_for_store.sh /путь/другой_out.zip
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_DIR="$REPO_ROOT/android"
APP_DIR="$ANDROID_DIR/app"
PROPS="$ANDROID_DIR/key.properties"
PEPK_JAR="$REPO_ROOT/pepk.jar"
OUT_ZIP="${1:-$ANDROID_DIR/pepk_out.zip}"

if [[ -f "$ANDROID_DIR/.signing_env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ANDROID_DIR/.signing_env"
  set +a
fi

PEPK_KEY_FILE="$ANDROID_DIR/.pepk_encryption_key"
if [[ -z "${PEPK_ENCRYPTION_KEY:-}" && -f "$PEPK_KEY_FILE" ]]; then
  PEPK_ENCRYPTION_KEY="$(grep -v '^[[:space:]]*#' "$PEPK_KEY_FILE" | head -1 | tr -d '\n\r \t')"
fi

if [[ ! -f "$PEPK_JAR" ]]; then
  echo "Нет pepk.jar: $PEPK_JAR"
  exit 1
fi

if [[ ! -f "$PROPS" ]]; then
  echo "Нет $PROPS"
  echo "Скопируйте шаблон: cp android/key.properties.example android/key.properties"
  echo "Заполните пароли, alias и положите upload-keystore.jks в корень проекта (или укажите storeFile)."
  exit 1
fi

if [[ -z "${PEPK_ENCRYPTION_KEY:-}" ]]; then
  echo "Нет ключа шифрования RuStore."
  echo "Вариант A: одна строка hex в android/.pepk_encryption_key"
  echo "Вариант B: export PEPK_ENCRYPTION_KEY='...' из окна «Загрузка подписи»"
  exit 1
fi

store_raw=$(grep '^storeFile=' "$PROPS" | cut -d= -f2- | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
key_alias=$(grep '^keyAlias=' "$PROPS" | cut -d= -f2- | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [[ -z "$store_raw" || -z "$key_alias" ]]; then
  echo "В key.properties нужны storeFile и keyAlias."
  exit 1
fi

if [[ -z "${STORE_PASSWORD:-}" ]]; then
  STORE_PASSWORD=$(grep '^storePassword=' "$PROPS" 2>/dev/null | cut -d= -f2- | tr -d '\r' || true)
fi
if [[ -z "${KEY_PASSWORD:-}" ]]; then
  KEY_PASSWORD=$(grep '^keyPassword=' "$PROPS" 2>/dev/null | cut -d= -f2- | tr -d '\r' || true)
fi

export PEPK_STORE_REL="$store_raw"
export PEPK_REPO="$REPO_ROOT"

if ! keystore_path="$(python3 <<'PY'
import os
import sys

raw = os.environ["PEPK_STORE_REL"].strip()
repo = os.environ["PEPK_REPO"]

if os.path.isabs(raw):
    if os.path.isfile(raw):
        print(raw)
        sys.exit(0)
    print(f"Нет файла: {raw}", file=sys.stderr)
    sys.exit(1)

bases = [
    os.path.join(repo, "android", "app"),
    os.path.join(repo, "android"),
    repo,
]
for base in bases:
    p = os.path.normpath(os.path.join(base, raw))
    if os.path.isfile(p):
        print(p)
        sys.exit(0)

guess = os.path.normpath(os.path.join(bases[0], raw))
print(
    f"storeFile={raw!r}: файл не найден. Ожидание от android/app: {guess}",
    file=sys.stderr,
)
sys.exit(1)
PY
)"; then
  echo ""
  echo "Положите .jks и выровняйте storeFile в key.properties."
  echo "Частый вариант: ключ в корне репо → storeFile=../upload-keystore.jks"
  exit 1
fi

echo "Репозиторий: $REPO_ROOT"
echo "Keystore:    $keystore_path"
echo "Alias:       $key_alias"
echo "Выход:       $OUT_ZIP"
echo ""

JAVA_ARGS=(
  -jar "$PEPK_JAR"
  --keystore "$keystore_path"
  --alias "$key_alias"
  --output "$OUT_ZIP"
  --encryptionkey="$PEPK_ENCRYPTION_KEY"
  --include-cert
)

if [[ -n "${STORE_PASSWORD}" && -n "${KEY_PASSWORD}" ]]; then
  printf '%s\n%s\n' "$STORE_PASSWORD" "$KEY_PASSWORD" | java "${JAVA_ARGS[@]}"
  echo ""
  echo "Готово: $OUT_ZIP"
else
  echo "В key.properties нет storePassword/keyPassword (или пустые). Введите пароли вручную."
  java "${JAVA_ARGS[@]}"
fi
