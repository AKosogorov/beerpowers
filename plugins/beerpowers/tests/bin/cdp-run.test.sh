#!/bin/sh
# cdp-run.mjs на учебном сайте (cdp-run-site.mjs): пример скилла page-screenshot целиком
# со своими проверками, ширины проекта по viewport "*", падение по времени со снимком
# и состоянием, перекрытый элемент, обрыв запроса подменой, подмена с ответом не-JSON,
# фильтр --only, отказ на файле сценариев до запуска Chrome.
#
# Без Chrome на машине проверяется только отказ на файле сценариев, остальное пропускается
# строкой skip с причиной. На Linux в CI Chrome идёт с --no-sandbox: у раннера нет
# пространств имён пользователя, которые нужны песочнице.
#
# Запуск: sh plugins/beerpowers/tests/bin/cdp-run.test.sh

here=$(cd -- "$(dirname -- "$0")" && pwd)
plugin=$(cd -- "$here/../.." && pwd)
tool="$plugin/templates/bin/cdp-run.mjs"
examples="$plugin/skills/page-screenshot/examples"

tmp=$(mktemp -d 2>/dev/null) || tmp="${TMPDIR:-/tmp}/bp-cdprun-$$"
mkdir -p "$tmp" || exit 2
site_pid=
trap '[ -n "$site_pid" ] && kill "$site_pid" 2>/dev/null; rm -rf "$tmp"' EXIT

# Пути внутрь JSON и в аргументы node — в форме, которую понимает node этой системы (на Windows — C:/…).
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

ws="$tmp/ws"
mkdir -p "$ws/.claude"
printf '{ "beerpowers": "2.7.0", "ui": true }\n' > "$ws/.claude/workspace.json"
run() { (cd "$tmp" && WORKSPACE_ROOT=$(native "$ws") node "$tool" "$@" 2>&1); }

total=0
failed=0
ok() { total=$((total + 1)); echo "pass  $1"; }
ko() { total=$((total + 1)); failed=$((failed + 1)); echo "FAIL  $1"; [ -n "$2" ] && printf '%s\n' "$2" | head -n 20 | sed 's/^/      /'; }
has() { printf '%s\n' "$1" | grep -q -- "$2"; }
# jq-free чтение JSONL: node -e с выражением над массивом строк r.
jsonl() { node -e "const r=require('fs').readFileSync(process.argv[1],'utf8').split('\n').filter(Boolean).map(JSON.parse);console.log(String($2))" "$(native "$1")"; }

# 1. Файл сценариев с ошибками — отказ кодом 2 со всеми ошибками сразу, Chrome не нужен.
cat > "$tmp/bad.json" <<'EOF'
{ "scenarios": [
  { "name": "a", "width": 800, "height": 600, "steps": [
    { "goto": "/x" },
    { "click": "a", "type": "b", "text": "c" },
    { "wait": { "selector": ".a", "expr": "1" } },
    { "press": "F13" },
    { "sleep": 1000 }
  ] },
  { "name": "a", "viewport": "tablet", "steps": [{ "goto": "http://127.0.0.1/" }] }
] }
EOF
out=$(run "$(native "$tmp/bad.json")" --out "$(native "$tmp/bad.jsonl")")
code=$?
if [ "$code" = 2 ] && has "$out" 'относительный адрес /x без baseUrl' && has "$out" 'одно действие из' \
  && has "$out" 'wait — одно условие' && has "$out" 'клавиша F13 неизвестна' && has "$out" 'ни одного' \
  && has "$out" 'viewport «tablet» нет' && [ ! -e "$tmp/bad.jsonl" ]; then
  ok "файл сценариев с ошибками — код 2, все ошибки, прогон не начат"
else ko "файл сценариев с ошибками — код 2, все ошибки, прогон не начат (код $code)" "$out"; fi

if ! node "$plugin/templates/bin/cdp-screenshot.mjs" --find-chrome >/dev/null 2>&1; then
  echo "skip  прогоны в браузере — Chrome не найден ($(node "$plugin/templates/bin/cdp-screenshot.mjs" --find-chrome 2>&1 | head -n 1))"
  echo
  echo "$total случаев, упало $failed"
  [ "$failed" = 0 ]
  exit
fi
[ "$(uname -s)" = Linux ] && [ -n "$CI" ] && export BEERPOWERS_CHROME_ARGS=--no-sandbox

node "$here/cdp-run-site.mjs" > "$tmp/site.log" 2>&1 &
site_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  port=$(sed -n 's/^port=//p' "$tmp/site.log")
  [ -n "$port" ] && break
  sleep 1
done
[ -n "$port" ] || { echo "учебный сайт не поднялся: $(cat "$tmp/site.log")"; exit 2; }
base="http://127.0.0.1:$port"

# 2. Пример скилла: viewport "*" — сценарий на каждую ширину проекта (по умолчанию mobile
# и desktop), подмены mergePatch и json, вход, сохранение 302 → 200, скриншот по ширине.
out=$(run "$(native "$examples/form-save.json")" --out "$(native "$tmp/ex/out.jsonl")" --base-url "$base")
code=$?
if [ "$code" = 0 ] && has "$out" '^ok    save-blocked@mobile' && has "$out" '^ok    save-ok@desktop' \
  && has "$out" '^TOTAL scenarios=5 failed=0' && [ -s "$tmp/tester-office-saved-375.png" ] && [ -s "$tmp/tester-office-saved-1440.png" ]; then
  ok "пример скилла проходит на каждой ширине, скриншоты по ширине"
else ko "пример скилла проходит на каждой ширине, скриншоты по ширине (код $code)" "$out"; fi

out=$(node "$examples/assert.mjs" "$(native "$tmp/ex/out.jsonl")" 2>&1)
code=$?
if [ "$code" = 0 ] && has "$out" '^TOTAL checks=28 failed=0'; then
  ok "проверки примера по JSONL зелёные"
else ko "проверки примера по JSONL зелёные (код $code)" "$out"; fi

got=$(jsonl "$tmp/ex/out.jsonl" "r.find(x => x.name === 'save-ok@mobile').network.find(n => n.method === 'POST' && n.url.endsWith('/login')).redirects[0].status + ' ' + r[0].network.find(n => n.url.endsWith('/api/offices')).mocked")
if [ "$got" = "302 GET */api/offices" ]; then
  ok "сеть: редирект записан цепочкой, подменённый запрос помечен шаблоном"
else ko "сеть: редирект записан цепочкой, подменённый запрос помечен шаблоном" "$got"; fi

# 3. Падения: время ожидания вышло — снимок и состояние в момент падения; элемент перекрыт;
# подмена обрывает запрос; mergePatch на ответе не-JSON. Каждое — FAIL своего сценария,
# соседние сценарии идут дальше, код 1.
cat > "$tmp/fail.json" <<EOF
{ "baseUrl": "$base", "timeout": 2000, "scenarios": [
  { "name": "timeout", "width": 800, "height": 600,
    "steps": [{ "goto": "/login" }, { "wait": { "selector": ".nope", "timeout": 300 } }],
    "state": { "path": "location.pathname" } },
  { "name": "covered", "width": 800, "height": 600,
    "steps": [
      { "goto": "/edit" }, { "type": "input[name=email]", "text": "admin@localhost" },
      { "type": "input[name=password]", "text": "password" }, { "submit": "form" },
      { "wait": { "url": "/edit" } }, { "click": "button", "hasText": "Сохранить", "timeout": 200 }
    ] },
  { "name": "abort", "width": 800, "height": 600,
    "mocks": [{ "url": "*/api/offices", "abort": true }],
    "steps": [
      { "goto": "/edit" }, { "type": "input[name=email]", "text": "admin@localhost" },
      { "type": "input[name=password]", "text": "password" }, { "press": "Enter" },
      { "wait": { "url": "/edit" } }, { "wait": { "networkIdle": 200 } }
    ] },
  { "name": "not-json", "width": 800, "height": 600,
    "mocks": [{ "url": "*/login", "method": "GET", "mergePatch": { "a": 1 } }],
    "steps": [{ "goto": "/login" }] },
  { "name": "fine", "width": 800, "height": 600, "steps": [{ "goto": "/login" }, { "wait": { "selector": "input[name=email]" } }] }
] }
EOF
out=$(run "$(native "$tmp/fail.json")" --out "$(native "$tmp/fail/out.jsonl")")
code=$?
if [ "$code" = 1 ] && has "$out" '^FAIL  timeout .*шаг 1 wait selector .nope: не дождались за 300 мс' \
  && has "$out" '^FAIL  covered .*перекрыт: div#hint' && has "$out" '^FAIL  not-json .*не JSON' \
  && has "$out" '^ok    abort' && has "$out" '^ok    fine' && has "$out" '^TOTAL scenarios=5 failed=3' \
  && [ -s "$tmp/fail/timeout-FAIL.png" ]; then
  ok "падения — FAIL с шагом и причиной, снимок падения, остальные идут дальше, код 1"
else ko "падения — FAIL с шагом и причиной, снимок падения, остальные идут дальше, код 1 (код $code)" "$out"; fi

got=$(jsonl "$tmp/fail/out.jsonl" "r[0].state.path + ' ' + r[0].error.step + ' ' + Boolean(r[2].network.find(n => n.url.endsWith('/api/offices')).failed) + ' ' + r[2].console.some(c => c.level === 'exception')")
if [ "$got" = "/login 1 true true" ]; then
  ok "состояние снято и после падения, обрыв подменой виден в сети и в console"
else ko "состояние снято и после падения, обрыв подменой виден в сети и в console" "$got"; fi

# 4. --only — только названные сценарии; имя до @ берёт все ширины.
out=$(run "$(native "$examples/form-save.json")" --out "$(native "$tmp/only.jsonl")" --base-url "$base" --only save-blocked)
code=$?
if [ "$code" = 0 ] && has "$out" '^TOTAL scenarios=2 failed=0' && ! has "$out" 'save-ok'; then
  ok "--only по имени до @ — все ширины одного сценария"
else ko "--only по имени до @ — все ширины одного сценария (код $code)" "$out"; fi

echo
echo "$total случаев, упало $failed"
[ "$failed" = 0 ]
