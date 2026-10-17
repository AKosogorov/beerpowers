#!/bin/sh
# yandex-tracker без сети: curl подменён заглушкой в PATH, которая пишет заголовки запроса
# в журнал и отвечает кодом по заголовку организации. Проверяется то, что у живого трекера
# не воспроизвести по заказу: порядок источников доступа (окружение → проект → глобальный
# файл, каждый ключ отдельно) и автоопределение типа организации по 401/403.
#
# Запуск: sh plugins/beerpowers/tests/bin/yandex-tracker.test.sh

here=$(cd -- "$(dirname -- "$0")" && pwd)
src="$here/../../templates/bin/yandex-tracker"

tmp=$(mktemp -d 2>/dev/null) || tmp="${TMPDIR:-/tmp}/bp-yt-$$"
mkdir -p "$tmp" || exit 2
trap 'rm -rf "$tmp"' EXIT

ws="$tmp/ws"
mkdir -p "$ws/.claude/bin" "$tmp/stub" "$tmp/home/.claude"
sed 's/{{BEERPOWERS_VERSION}}/0.0.0/' "$src" > "$ws/.claude/bin/yandex-tracker"
chmod +x "$ws/.claude/bin/yandex-tracker"

# Заглушка curl: тело ответа, перевод строки, код — как у `curl -w '\n%{http_code}'`.
# STUB_CLOUD — код на заголовок X-Cloud-Org-ID, на X-Org-ID — всегда 200.
cat > "$tmp/stub/curl" <<'EOF'
#!/bin/sh
for a in "$@"; do
  case "$a" in
    Authorization:*|X-Cloud-Org-ID:*|X-Org-ID:*) printf '%s\n' "$a" >> "$STUB_LOG" ;;
  esac
done
printf -- '---\n' >> "$STUB_LOG"
case "$*" in
  *X-Cloud-Org-ID:*) code=${STUB_CLOUD:-200} ;;
  *) code=200 ;;
esac
if [ "$code" = 200 ]; then
  printf '{"key":"Q-1","summary":"Проверка"}\n200'
else
  printf '{}\n%s' "$code"
fi
EOF
chmod +x "$tmp/stub/curl"

total=0
failed=0

# run <имя> <ожидание>…: текст — есть в выводе; log:текст — есть в журнале запросов заглушки,
# nolog:текст — нет в нём. Переменные окружения прогона — в case_env.
run() {
  name=$1
  shift
  total=$((total + 1))
  : > "$tmp/log"
  out=$(env -u YANDEX_TRACKER_TOKEN -u YANDEX_TRACKER_ORG_ID -u YANDEX_TRACKER_ORG_TYPE \
    PATH="$tmp/stub:$PATH" CLAUDE_CONFIG_DIR="$tmp/home/.claude" STUB_LOG="$tmp/log" \
    $case_env bash "$ws/.claude/bin/yandex-tracker" Q-1 2>&1)
  printf '%s\n' "$out" >> "$tmp/all-out"
  ok=1
  for want in "$@"; do
    case "$want" in
      log:*) grep -qF -- "${want#log:}" "$tmp/log" || { ok=0; why="в запросах нет «${want#log:}»"; } ;;
      nolog:*) grep -qF -- "${want#nolog:}" "$tmp/log" && { ok=0; why="в запросах есть «${want#nolog:}»"; } ;;
      *) printf '%s' "$out" | grep -qF -- "$want" || { ok=0; why="в выводе нет «$want»"; } ;;
    esac
  done
  if [ "$ok" = 1 ]; then
    echo "pass  $name"
  else
    failed=$((failed + 1))
    echo "FAIL  $name — $why"
    printf '%s\n' "$out" | sed 's/^/      out: /' | head -5
    sed 's/^/      log: /' "$tmp/log" | head -6
  fi
}

project="$ws/.claude/yandex-tracker-settings.json"
global="$tmp/home/.claude/yandex-tracker-settings.json"

printf '%s\n' '{ "token": "proj-tok", "orgId": "proj-org" }' > "$project"
printf '%s\n' '{ "token": "glob-tok", "orgId": "glob-org" }' > "$global"
case_env="YANDEX_TRACKER_TOKEN=env-tok"
run 'окружение выигрывает у файлов' 'log:Authorization: OAuth env-tok' 'log:X-Cloud-Org-ID: proj-org'

printf '%s\n' '{ "orgId": "proj-org" }' > "$project"
case_env=""
run 'каждый ключ отдельно: orgId из проекта, токен из глобального' 'log:OAuth glob-tok' 'log:: proj-org' 'nolog:glob-org'

rm -f "$project"
run 'проектного файла нет — всё из глобального' 'log:OAuth glob-tok' 'log:: glob-org' '# Q-1 · Проверка'

case_env="STUB_CLOUD=403"
run 'тип не задан: cloud отказал — повтор с X-Org-ID и подсказка' 'log:X-Org-ID: glob-org' '"orgType": "yandex360"' '# Q-1 · Проверка'

printf '%s\n' '{ "token": "glob-tok", "orgId": "glob-org", "orgType": "yandex360" }' > "$global"
case_env="STUB_CLOUD=403"
run 'orgType yandex360 — сразу X-Org-ID, без пробы cloud' 'log:X-Org-ID: glob-org' 'nolog:X-Cloud-Org-ID'

printf '%s\n' '{ "orgId": "glob-org" }' > "$global"
case_env=""
run 'токена нет нигде — отказ с местами, где его ждут' 'нет YANDEX_TRACKER_TOKEN'

total=$((total + 1))
if grep -qF -- '-tok' "$tmp/all-out"; then
  failed=$((failed + 1)); echo "FAIL  значение токена попало в вывод"
else
  echo "pass  значение токена не печатается ни в одном прогоне"
fi

echo
echo "$total случаев, упало $failed"
[ "$failed" = 0 ]
