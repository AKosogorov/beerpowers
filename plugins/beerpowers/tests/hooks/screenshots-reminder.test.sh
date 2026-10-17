#!/bin/sh
# Фикстуры templates/hooks/screenshots-reminder.sh: событие старта роли, затем остановка.
# Ожидание — код выхода хука: 0 выпустить роль, 2 вернуть с напоминанием. Печатает pass/fail,
# код выхода ненулевой, если упал хоть один случай.
#
# Запуск: sh plugins/beerpowers/tests/hooks/screenshots-reminder.test.sh

here=$(cd -- "$(dirname -- "$0")" && pwd)
hook_sh="$here/../../templates/hooks/screenshots-reminder.sh"
tmp=$(mktemp -d 2>/dev/null) || tmp="${TMPDIR:-/tmp}/bp-screenshots-$$"
mkdir -p "$tmp" || exit 2
trap 'rm -rf "$tmp"' EXIT

failed=0
total=0

project() {
  rm -rf "$tmp/p"
  mkdir -p "$tmp/p/.claude" "$tmp/p/memory/tasks/T-1/screenshots" "$tmp/p/memory/tasks/T-1/figma"
  cat > "$tmp/p/.claude/team-charter.md" <<'EOF'
# Charter

## Состав

| Роль | subagent_type | Миссия |
|---|---|---|
| `front` | frontend-agent | UI |
| `tester` | testing-agent | прогоны |

## Файлы памяти
EOF
  printf '{\n  "beerpowers": "2.0.0"\n}\n' > "$tmp/p/.claude/workspace.json"
}

hook() {
  ev=$1; id=$2; type=$3; shift 3
  printf '{"hook_event_name":"%s","session_id":"s1","agent_id":"%s","agent_type":"%s"}' "$ev" "$id" "$type" \
    | CLAUDE_PROJECT_DIR="$tmp/p" sh "$hook_sh" "$@" >/dev/null 2>"$tmp/err"
}

expect() {
  total=$((total + 1))
  if [ "$2" = "$3" ]; then echo "pass  $1"; else echo "FAIL  $1 (ждали $3, получили $2)"; failed=$((failed + 1)); fi
}

# Старт и остановка — с паузой: метка и скриншот в одну секунду на ФС с грубым временем
# неразличимы, -newer требует строго позже.
start_role() { hook SubagentStart a1 testing-agent; sleep 1; }

project; start_role
: > "$tmp/p/memory/tasks/T-1/screenshots/tester-cart-375.png"
hook SubagentStop a1 testing-agent; expect "скриншот tester свежее старта — проход" "$?" 0

project; start_role
: > "$tmp/p/memory/tasks/T-1/screenshots/front-cart-375.png"
hook SubagentStop a1 testing-agent; expect "только скриншот front — напоминание" "$?" 2

project; start_role
hook SubagentStop a1 testing-agent; expect "пусто — напоминание" "$?" 2
hook SubagentStop a1 testing-agent; expect "повтор той же роли — проход" "$?" 0

project
: > "$tmp/p/memory/tasks/T-1/screenshots/tester-cart-375.png"
sleep 1; start_role
hook SubagentStop a1 testing-agent; expect "скриншот tester старше старта роли — напоминание" "$?" 2

project; start_role
: > "$tmp/p/memory/tasks/T-1/figma/tester-cart-375.png"
hook SubagentStop a1 testing-agent; expect "фрейм в figma/, не в screenshots/ — напоминание" "$?" 2

project
: > "$tmp/p/memory/tasks/T-1/screenshots/tester-cart-375.png"
hook SubagentStop a1 testing-agent; expect "метки старта нет, свежий скриншот в окне — проход" "$?" 0

project
hook SubagentStop a1 testing-agent
grep -q 'запасной режим' "$tmp/err"; expect "метки старта нет — напоминание говорит про запасной режим" "$?" 0

project; start_role
hook SubagentStop a1 testing-agent
grep -q 'Скриншоты: не снимались' "$tmp/err"; expect "напоминание даёт выход строкой в отчёте" "$?" 0

project; start_role
hook SubagentStop a1 testing-agent
hook SubagentStart b1 testing-agent; sleep 1
hook SubagentStop b1 testing-agent; expect "второй тестер в той же сессии — своё напоминание" "$?" 2

project; start_role
hook SubagentStop a2 frontend-agent; expect "другая роль — хук молчит" "$?" 0

project; rm "$tmp/p/.claude/team-charter.md"; start_role
hook SubagentStop a1 testing-agent; expect "нет charter — хук молчит" "$?" 0

project; start_role
mkdir -p "$tmp/p/screenshots-elsewhere"; : > "$tmp/p/screenshots-elsewhere/tester-x-375.png"
hook SubagentStop a1 testing-agent --dir "$tmp/p/screenshots-elsewhere"; expect "явный --dir — проход" "$?" 0

echo
echo "$total случаев, упало $failed"
[ "$failed" -eq 0 ]
