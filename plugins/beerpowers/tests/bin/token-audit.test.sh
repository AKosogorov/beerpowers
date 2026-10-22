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

echo
echo "$total случаев, упало $failed"
[ "$failed" = 0 ]
