#!/bin/bash
# Конвейер индекса: сканирует приложения на симуляторе и собирает сайт.
#
# Почему bash, а не Swift: шаг сканирования — это запуск xcodebuild, который
# сам по себе процесс с окружением и таймаутами. Обёртывать его в программу
# значит переписывать оболочку, ничего не выигрывая.
#
# Использование:
#   Scripts/scan-and-build-index.sh apps.txt
#
# Формат apps.txt, по строке на приложение:
#   bundle.id|Имя приложения|локаль|сколько экранов
# Строки, начинающиеся с #, игнорируются.

set -euo pipefail

MANIFEST="${1:-Scripts/apps.txt}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM="${A11Y_SIMULATOR:-iPhone 17 Pro}"
BASELINES="$ROOT/.index-baselines"
DOCS="$ROOT/docs"

[ -f "$MANIFEST" ] || { echo "нет файла со списком приложений: $MANIFEST" >&2; exit 1; }

mkdir -p "$BASELINES"

# Список установленных приложений снимается ОДИН раз.
#
# Не только ради скорости. Проверка вида `simctl listapps | grep -q` вместе
# с `set -o pipefail` даёт ложный отрицательный ответ всегда: grep -q
# закрывает канал на первом совпадении, simctl получает SIGPIPE и завершается
# с ошибкой, pipefail поднимает её на весь конвейер. Скрипт при этом
# сообщает «не установлено» про каждое приложение и молча ничего не делает.
INSTALLED=$(xcrun simctl listapps booted </dev/null 2>/dev/null || true)

echo "Симулятор: $SIM"
echo "Список:    $MANIFEST"
echo

scanned=0
skipped=0

# Список читается через дескриптор 3, а команды внутри цикла получают
# /dev/null на вход. Без этого xcrun и xcodebuild съедают stdin вместе
# с остатком списка, и цикл молча обрабатывает одну строку вместо всех.
while IFS='|' read -r bundle name locale screens <&3; do
  # Пропускаем комментарии и пустые строки.
  [[ -z "${bundle// }" || "${bundle:0:1}" == "#" ]] && continue

  echo "→ $name ($bundle)"

  # Приложение должно быть установлено. Проверяем заранее: иначе тест
  # упадёт по таймауту запуска, а это пять минут на каждую опечатку.
  if [[ "$INSTALLED" != *"\"$bundle\""* ]]; then
    echo "  пропущено: не установлено на симуляторе"
    skipped=$((skipped + 1))
    continue
  fi

  output=$(cd "$ROOT/Examples/Scanner" && \
    TEST_RUNNER_A11Y_BUNDLE_ID="$bundle" \
    TEST_RUNNER_A11Y_APP_NAME="$name" \
    TEST_RUNNER_A11Y_LOCALE="${locale:-ru}" \
    TEST_RUNNER_A11Y_MAX_SCREENS="${screens:-1}" \
    xcodebuild test -project A11yScanner.xcodeproj -scheme A11yScannerUITests \
      -destination "platform=iOS Simulator,name=$SIM" 2>&1 | grep -E "A11Y_SCAN_" || true)

  path=$(echo "$output" | grep "A11Y_SCAN_OUTPUT=" | head -1 | cut -d= -f2- || true)
  if [ -z "$path" ] || [ ! -f "$path" ]; then
    echo "  пропущено: сканирование не дало результата"
    skipped=$((skipped + 1))
    continue
  fi

  cp "$path" "$BASELINES/$(echo "$bundle" | tr '.' '-').json"
  echo "  $(echo "$output" | grep A11Y_SCAN_ELEMENTS= | cut -d= -f2) элементов, $(echo "$output" | grep A11Y_SCAN_FINDINGS= | cut -d= -f2) находок"
  scanned=$((scanned + 1))
done 3< "$MANIFEST"

echo
echo "Просканировано: $scanned, пропущено: $skipped"
[ "$scanned" -gt 0 ] || { echo "нечего собирать" >&2; exit 1; }

swift run --package-path "$ROOT" a11y-report --index "$BASELINES" "$DOCS"
