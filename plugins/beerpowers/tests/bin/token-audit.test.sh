#!/bin/sh
# token-audit.mjs на фикстуре логов: главная сессия и два захода Explore на разных моделях.
# Раздел «РОЛЬ × МОДЕЛЬ» разводит заходы одной роли по моделям — по нему видно, что тир роли
# без своего файла не дошёл до вызова; usage одного запроса, разбитого на несколько строк,
# считается один раз.
#
# Запуск: sh plugins/beerpowers/tests/bin/token-audit.test.sh

here=$(cd -- "$(dirname -- "$0")" && pwd)
tool="$here/../../templates/bin/token-audit.mjs"

tmp=$(mktemp -d 2>/dev/null) || tmp="${TMPDIR:-/tmp}/bp-token-audit-$$"
mkdir -p "$tmp" || exit 2
trap 'rm -rf "$tmp"' EXIT

native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

# row <requestId> <модель> — строка assistant с usage; один запрос пишется двумя строками.
row() {
  printf '{"type":"assistant","requestId":"%s","timestamp":"2026-10-20T00:00:00Z","message":{"model":"%s","usage":{"input_tokens":100,"output_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[]}}\n' "$1" "$2"
}

logs="$tmp/logs"
mkdir -p "$logs/s1/subagents"
{ row m1 claude-opus-5-5; row m1 claude-opus-5-5; } > "$logs/s1.jsonl"
{ row a1 claude-sonnet-5-5; row a1 claude-sonnet-5-5; row a2 claude-sonnet-5-5; } > "$logs/s1/subagents/agent-a.jsonl"
printf '{"agentType":"Explore","description":"поиск по техдолгу"}\n' > "$logs/s1/subagents/agent-a.meta.json"
row b1 claude-haiku-5-5 > "$logs/s1/subagents/agent-b.jsonl"
printf '{"agentType":"Explore","description":"поиск вызовов"}\n' > "$logs/s1/subagents/agent-b.meta.json"

total=0
failed=0
ok() { total=$((total + 1)); echo "pass  $1"; }
ko() { total=$((total + 1)); failed=$((failed + 1)); echo "FAIL  $1"; [ -n "$2" ] && printf '%s\n' "$2" | sed 's/^/      /'; }

out=$(node "$tool" --dir "$(native "$logs")" 2>&1)
code=$?
section=$(printf '%s\n' "$out" | sed -n '/=== РОЛЬ × МОДЕЛЬ ===/,/^$/p')
if [ "$code" = 0 ] \
  && printf '%s\n' "$section" | grep -q '^Explore .*claude-sonnet-5-5 .*заходов    1  запросов       2 ' \
  && printf '%s\n' "$section" | grep -q '^Explore .*claude-haiku-5-5 .*заходов    1  запросов       1 ' \
  && printf '%s\n' "$section" | grep -q '^MAIN .*claude-opus-5-5 .*запросов       1 '; then
  ok "роль × модель: заходы одной роли разведены по моделям, запрос из двух строк — один"
else ko "роль × модель: заходы одной роли разведены по моделям, запрос из двух строк — один (код $code)" "$out"; fi

node "$tool" --dir "$(native "$logs")" --json "$(native "$tmp/report.json")" > /dev/null 2>&1
got=$(node -e "const r=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log(r.roleModelRows.map(x=>x.role+'/'+x.model+'/'+x.requests).join(' '))" "$(native "$tmp/report.json")")
if [ "$got" = "Explore/claude-sonnet-5-5/2 Explore/claude-haiku-5-5/1 MAIN/claude-opus-5-5/1" ]; then
  ok "роль × модель в --json"
else ko "роль × модель в --json" "$got"; fi

# Второй корпус — с временем: заход backend-agent на Opus ждёт тесты 7 минут и после них
# перезаписывает кеш, читает картинку; заход testing-agent на Sonnet ждёт сообщения 20 минут.
# Запрос после --until в отчёт не идёт.
# ev <время> <requestId> <input> <read> <write> <модель> [<блок content>] — запрос модели.
ev() {
  printf '{"type":"assistant","requestId":"%s","timestamp":"2026-10-20T%sZ","message":{"model":"%s","usage":{"input_tokens":%s,"output_tokens":10,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s},"content":[%s]}}\n' "$2" "$1" "$6" "$3" "$4" "$5" "${7:-}"
}
# res <время> <id вызова> <содержимое tool_result> [<toolUseResult>] — ответ инструмента.
res() {
  printf '{"type":"user","timestamp":"2026-10-20T%sZ","toolUseResult":%s,"message":{"content":[{"type":"tool_result","tool_use_id":"%s","content":%s}]}}\n' "$1" "${4:-\"ok\"}" "$2" "$3"
}
logs2="$tmp/logs2"
mkdir -p "$logs2/s2/subagents"
ev 09:00:00 m1 100 0 1000 claude-opus-5-5 > "$logs2/s2.jsonl"
{
  ev 10:00:00 b1 100 0 50000 claude-opus-5-5 '{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"npm --prefix projects/shop-backend run test"}}'
  res 10:07:00 t1 '"ok"'
  ev 10:07:30 b2 100 10000 40000 claude-opus-5-5 '{"type":"tool_use","id":"t2","name":"Read","input":{"file_path":"D:\\ws\\projects\\shop-frontend\\shot.png"}}'
  res 10:08:00 t2 '[{"type":"image","source":{"type":"base64","data":"QUJD"}}]' '{"type":"image","file":{"base64":"QUJD"}}'
  ev 10:08:10 b3 100 50000 900 claude-opus-5-5
} > "$logs2/s2/subagents/agent-b.jsonl"
printf '{"agentType":"backend-agent","description":"фича"}\n' > "$logs2/s2/subagents/agent-b.meta.json"
{
  ev 11:00:00 q1 100 0 40000 claude-sonnet-5-5
  printf '{"type":"user","timestamp":"2026-10-20T11:20:00Z","message":{"content":"дальше"}}\n'
  ev 11:20:00 q2 100 0 60000 claude-sonnet-5-5
  printf '{"type":"assistant","requestId":"late","timestamp":"2026-10-25T00:00:00Z","message":{"model":"claude-sonnet-5-5","usage":{"input_tokens":100,"output_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[]}}\n'
} > "$logs2/s2/subagents/agent-t.jsonl"
printf '{"agentType":"testing-agent","description":"прогон"}\n' > "$logs2/s2/subagents/agent-t.meta.json"

out=$(node "$tool" --dir "$(native "$logs2")" --since 2026-10-20T00:00:00Z --until 2026-10-21T00:00:00Z --time --by-repo 2>&1)
code=$?
has() { printf '%s\n' "$out" | grep -qF -- "$1"; }
check() { if [ "$code" = 0 ] && has "$2"; then ok "$1"; else ko "$1 (код $code)" "$(printf '%s\n' "$out" | sed -n "/$3/,/^\$/p")"; fi; }
check "период: граница в UTC, запрос после --until не идёт" "период (UTC): 2026-10-20T00:00:00Z — 2026-10-21T00:00:00Z" "период"
check "период: заход вне периода целиком — не в счёте" "запросов 6 " "запросов"
check "перезапись кеша: после долгого вызова инструмента" "пауза: долгий вызов инструмента  запросов     1" "ПЕРЕЗАПИСЬ"
check "перезапись кеша: после ожидания сообщения" "пауза: ожидание сообщения        запросов     1" "ПЕРЕЗАПИСЬ"
check "перезапись кеша: доля в деньгах на запись" "из них после паузы > 5 мин: запросов 2" "ПЕРЕЗАПИСЬ"
check "картинка — токенами записи следующего запроса, не байтами" "медиана 900, макс 900 токенов на картинку" "КАРТИНКИ"
check "стартовый контекст захода по ролям" "backend-agent      заходов    1  медиана   50k" "СТАРТОВЫЙ"
check "время: категория тестов по команде Bash" "тесты 7" "ВРЕМЯ"
check "время: стена захода, медиана" "testing-agent      заходов    1  сумма    20" "ВРЕМЯ"
check "репозитории: путь projects/<репо> с прямым слэшем" "shop-backend" "РЕПОЗИТОРИЯМ"
check "репозитории: путь с обратными слэшами" "shop-frontend" "РЕПОЗИТОРИЯМ"
check "репозитории: заход без путей" "без репозитория" "РЕПОЗИТОРИЯМ"
if printf '%s\n' "$out" | sed -n '/КРУПНЕЙШИЕ/,/^$/p' | grep -q 'shot.png'; then ko "картинка не в рейтинге по размеру" "$out"; else ok "картинка не в рейтинге по размеру"; fi

echo
echo "$total случаев, упало $failed"
[ "$failed" = 0 ]
