#!/bin/sh
# Фикстуры хуков плагина: каждый случай из cases.txt гоняется на свежем временном
# каталоге-проекте, собранном функцией fx_<фикстура>. Печатает pass/fail по случаю,
# код выхода ненулевой, если упал хоть один.
#
# Запуск: sh plugins/beerpowers/tests/hooks/run.sh [файл случаев]
#
# Формат строки cases.txt: <ожидание> | <хук> | <фикстура> | <имя> | <JSON на stdin>
# JSON стоит последним: `read` отдаёт последнему полю остаток строки целиком, поэтому `|`
# внутри команды не ломает разбор. Ожидания:
#   pass             — пустой вывод
#   deny             — вывод с "permissionDecision":"deny"
#   deny:<текст>     — отказ, в выводе есть <текст>
#   deny-then-pass   — первый вызов отказ, повтор того же входа на той же фикстуре — пропуск
#   has:<текст>      — в выводе есть <текст>
#   lacks:<текст>    — в выводе нет <текст>
# Код выхода хука во всех случаях обязан быть 0: ненулевой у PreToolUse — это уже решение.

here=$(cd -- "$(dirname -- "$0")" && pwd)
plugin=$(cd -- "$here/../.." && pwd)
cases_file=${1:-$here/cases.txt}

tmp_root=$(mktemp -d 2>/dev/null) || tmp_root="${TMPDIR:-/tmp}/bp-hooks-$$"
mkdir -p "$tmp_root" || exit 2
trap 'rm -rf "$tmp_root"' EXIT
trap 'exit 130' INT TERM

plugin_version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$plugin/.claude-plugin/plugin.json" | head -n 1)

# --- строительные блоки фикстур ---------------------------------------------------------

charter() {
  mkdir -p "$1/.claude"
  printf '# Charter\n\n%s\n' "${2:-generated-by: beerpowers v$plugin_version · mode: plugin-linked}" > "$1/.claude/team-charter.md"
}

ws() {
  mkdir -p "$1/.claude"
  printf '%s\n' "$2" > "$1/.claude/workspace.json"
}

repo() {
  git init -q "$1" >/dev/null 2>&1
  git -C "$1" config user.email hooks@example.invalid
  git -C "$1" config user.name hooks
  git -C "$1" config commit.gpgsign false
  printf 'init\n' > "$1/README"
  git -C "$1" add README
  git -C "$1" commit -q -m init >/dev/null 2>&1
  # Ветка задачи, уже отправленная на сервер: для guard-push её push — не первый.
  git -C "$1" update-ref refs/remotes/origin/PROJ-1 HEAD
  # Сервер не нужен: guard-push читает адрес remote и локальный origin/HEAD.
  git -C "$1" remote add origin https://gitlab.example.invalid/group/app.git
  git -C "$1" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master
}

# Ветка по умолчанию и хостинг remote origin: origin_head <каталог> <ветка> [<адрес>].
origin_head() {
  if [ -n "${2:-}" ]; then
    git -C "$1" symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/$2"
  else
    git -C "$1" symbolic-ref --delete refs/remotes/origin/HEAD
  fi
  [ -z "${3:-}" ] || git -C "$1" remote set-url origin "$3"
}

stage() {
  mkdir -p "$(dirname -- "$1/$2")"
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add -- "$2"
}

WS_PUSH_GITLAB='{
  "beerpowers": "2.0.0",
  "barriers": {
    "guard-push": true,
    "guard-kill": true,
    "guard-comments": true,
    "guard-commit-split": true
  }
}'

WS_ALL_OFF='{
  "beerpowers": "2.0.0",
  "barriers": {
    "guard-push": false,
    "guard-kill": false,
    "guard-comments": false,
    "guard-commit-split": false,
    "guard-approval-link": false,
    "guard-agent-memory": false
  }
}'

# --- фикстуры ---------------------------------------------------------------------------

fx_defaults() { charter "$1"; repo "$1"; }

fx_nocharter() {
  ws "$1" "$WS_PUSH_GITLAB"
  repo "$1"
  stage "$1" src/a.ts '// новый комментарий'
  stage "$1" memory/tasks/PROJ-1/review-report.md 'APPROVED'
}

fx_all_off() {
  charter "$1"
  ws "$1" "$WS_ALL_OFF"
  repo "$1"
  stage "$1" src/a.ts '// новый комментарий'
  stage "$1" memory/tasks/PROJ-1/review-report.md 'APPROVED'
}

fx_push() { charter "$1"; ws "$1" "$WS_PUSH_GITLAB"; repo "$1"; }

fx_push_github() {
  fx_push "$1"
  origin_head "$1" main https://github.com/org/app.git
}

fx_push_defaultbranch() {
  fx_push "$1"
  origin_head "$1" trunk
}

fx_push_devdefault() {
  fx_push "$1"
  origin_head "$1" dev
}

fx_push_nohead() {
  fx_push "$1"
  origin_head "$1" ''
}

fx_push_taskdir() {
  fx_push "$1"
  mkdir -p "$1/memory/tasks/fix-header-scroll"
}

fx_comments() {
  charter "$1"
  ws "$1" '{ "comments": { "excludeDirs": ["gen/api", "vendor/"] } }'
  repo "$1"
  stage "$1" src/a.ts '// пересказ строки'
  stage "$1" src/b.php '/* блок */'
}

# Исключения пишутся путём от корня workspace и действуют только в своём репозитории
# и его рабочих деревьях: projects/app/gen/api исключён, у projects/other — свой.
WS_EXCLUDE='{ "comments": { "excludeDirs": ["projects/app/gen/api", "projects/other/vendor/"] } }'

fx_comments_excluded() {
  charter "$1"
  ws "$1" "$WS_EXCLUDE"
  repo "$1/projects/app"
  stage "$1/projects/app" gen/api/client.ts '// сгенерировано'
}

fx_comments_other_repo() {
  charter "$1"
  ws "$1" "$WS_EXCLUDE"
  repo "$1/projects/app"
  stage "$1/projects/app" vendor/x.js '/* исключён только у other */'
}

fx_comments_worktree() {
  charter "$1"
  ws "$1" "$WS_EXCLUDE"
  repo "$1/worktrees/PROJ-1/app"
  stage "$1/worktrees/PROJ-1/app" gen/api/client.ts '// сгенерировано в дереве задачи'
}

# Копии плагина приходят целиком через /beerpowers:update — мимо показа; проектный скрипт
# рядом с ними, без шапки, показывается.
fx_comments_copies() {
  charter "$1"
  repo "$1"
  mkdir -p "$1/.claude/bin/lib"
  printf '%s\n' '#!/usr/bin/env node' '// generated by beerpowers v2.10.0 — не править: обновляет /beerpowers:update' '// комментарий копии' > "$1/.claude/bin/cdp-run.mjs"
  printf '%s\n' '#!/usr/bin/env bash' '# generated by beerpowers v2.10.0 — не править: обновляет /beerpowers:update' '# комментарий копии' > "$1/.claude/bin/lib/workspace.sh"
  git -C "$1" add .claude/bin
}

fx_comments_copies_own() {
  fx_comments_copies "$1"
  stage "$1" .claude/bin/testdb-ensure.sh '# свой скрипт проекта'
}

fx_comments_none() {
  charter "$1"
  repo "$1"
  stage "$1" src/a.ts 'const a = 1'
  stage "$1" src/u.ts 'const u = "https://example.invalid/a"'
  stage "$1" run.sh '#!/bin/sh'
  stage "$1" app/Attr.php '#[Attribute]'
  stage "$1" notes.py 'print(1)'
}

fx_comments_hash() {
  charter "$1"
  repo "$1"
  stage "$1" app/job.py '# пересказ на питоне'
}

fx_comments_trailing() {
  charter "$1"
  repo "$1"
  stage "$1" src/c.ts 'const a = 1 // хвостовой пересказ'
  stage "$1" deploy.yml 'replicas: 2 # хвост в yaml'
}

fx_comments_blade() {
  charter "$1"
  repo "$1"
  stage "$1" resources/views/a.blade.php '{{-- пересказ в blade --}}'
}

# Комментарий только в неиндексированной правке отслеживаемого файла: его видит `commit -a`,
# а обычный коммит индекса — нет.
fx_comments_unstaged() {
  charter "$1"
  repo "$1"
  stage "$1" src/a.ts 'const a = 1'
  git -C "$1" commit -q -m base >/dev/null 2>&1
  printf '%s\n' '// неиндексированный пересказ' >> "$1/src/a.ts"
}

fx_split_mixed() {
  charter "$1"
  repo "$1"
  stage "$1" memory/tasks/PROJ-1/review-report.md 'APPROVED'
  stage "$1" src/a.txt 'код'
}

fx_split_tasks_only() {
  charter "$1"
  repo "$1"
  stage "$1" memory/tasks/PROJ-1/review-report.md 'APPROVED'
  stage "$1" memory/tasks/PROJ-1/plan.md 'план'
}

fx_split_other_only() {
  charter "$1"
  repo "$1"
  stage "$1" src/a.txt 'код'
  stage "$1" memory/MEMORY.md 'индекс'
}

fx_split_key_ignored() {
  charter "$1"
  ws "$1" '{ "tasksDir": "work/tasks" }'
  repo "$1"
  stage "$1" memory/tasks/PROJ-1/review-report.md 'APPROVED'
  stage "$1" src/a.txt 'код'
}

fx_quality() {
  charter "$1"
  printf '%s\n' \
    '# гейты проекта' \
    '' \
    '*/database/migrations/*.php  Миграция: идемпотентность, индекс на FK.' \
    '*.php    PHP: статанализ, затем полный check.' \
    '*.yml    Конфигурация: "секреты" не в диффе.' > "$1/.claude/quality-gates.txt"
}

fx_nocharter_link_off() {
  printf '%s\n' 'export CLAUDE_PLUGIN_OPTION_REPLY_FILE_LINKS=false' > "$1/.env"
}
fx_nocharter_rules_off() {
  printf '%s\n' \
    'export CLAUDE_PLUGIN_OPTION_REPLY_FILE_LINKS=false' \
    'export CLAUDE_PLUGIN_OPTION_REPLY_USER_SHELL=false' \
    'export CLAUDE_PLUGIN_OPTION_REPLY_BLOCKING_ASKS=false' > "$1/.env"
}

fx_qtim() { charter "$1" 'generated-by: qtim v1.14.0 · mode: plugin-linked'; }
fx_bp_current() { charter "$1"; }
fx_bp_old() { charter "$1" 'generated-by: beerpowers v1.0.0 · mode: plugin-linked'; }

# --- прогон -----------------------------------------------------------------------------

hook_script() {
  case "$1" in
    quality-reminder) printf '%s' "$plugin/templates/hooks/quality-reminder.sh" ;;
    *) printf '%s' "$plugin/hooks/$1.sh" ;;
  esac
}

trim() {
  t=$1
  t=${t#"${t%%[! ]*}"}
  t=${t%"${t##*[! ]}"}
  printf '%s' "$t"
}

# Результат вызова кладётся в $dir/.out; код выхода — в rc.
call_hook() {
  printf '%s' "$json" > "$dir/.in"
  (
    cd "$dir" || exit 97
    # Опции плагина (CLAUDE_PLUGIN_OPTION_*) фикстура кладёт в .env: подоболочка не даёт
    # им утечь в следующие случаи.
    if [ -f "$dir/.env" ]; then . "$dir/.env"; fi
    # Аргумент нужен только session-start (корень плагина, как в hooks.json); остальным
    # первый аргумент значит другое — у quality-reminder это путь к файлу гейтов.
    if [ "$hook" = "session-start" ]; then
      CLAUDE_PROJECT_DIR=$dir sh "$script" "$plugin" < "$dir/.in" > "$dir/.out" 2> "$dir/.err"
    else
      CLAUDE_PROJECT_DIR=$dir sh "$script" < "$dir/.in" > "$dir/.out" 2> "$dir/.err"
    fi
  )
  rc=$?
}

is_deny() { grep -q '"permissionDecision":"deny"' "$dir/.out"; }
is_empty() { [ -z "$(tr -d ' \n\r\t' < "$dir/.out")" ]; }

total=0
failed=0
n=0

while IFS='|' read -r expect hook fixture name json || [ -n "$expect" ]; do
  expect=$(trim "$expect")
  case "$expect" in
    ''|'#'*) continue ;;
  esac
  hook=$(trim "$hook")
  fixture=$(trim "$fixture")
  name=$(trim "$name")
  json=$(trim "$json")

  n=$((n + 1))
  total=$((total + 1))
  dir="$tmp_root/case-$n"
  mkdir -p "$dir"
  script=$(hook_script "$hook")
  fx=$(printf '%s' "$fixture" | tr '-' '_')

  ok=1
  why=""
  if ! command -v "fx_$fx" >/dev/null 2>&1; then
    ok=0
    why="нет фикстуры $fixture"
  elif [ ! -f "$script" ]; then
    ok=0
    why="нет хука $script"
  else
    "fx_$fx" "$dir"
    call_hook
    if [ "$rc" != "0" ]; then
      ok=0
      why="код выхода $rc"
    else
      case "$expect" in
        pass)
          is_empty || { ok=0; why="ожидался пустой вывод"; }
          ;;
        deny)
          is_deny || { ok=0; why="ожидался deny"; }
          ;;
        deny:*)
          if ! is_deny; then
            ok=0; why="ожидался deny"
          elif ! grep -qF -- "${expect#deny:}" "$dir/.out"; then
            ok=0; why="в отказе нет «${expect#deny:}»"
          fi
          ;;
        has:*)
          grep -qF -- "${expect#has:}" "$dir/.out" || { ok=0; why="в выводе нет «${expect#has:}»"; }
          ;;
        lacks:*)
          if grep -qF -- "${expect#lacks:}" "$dir/.out"; then ok=0; why="в выводе есть «${expect#lacks:}»"; fi
          ;;
        deny-then-pass)
          if ! is_deny; then
            ok=0; why="первый вызов: ожидался deny"
          else
            call_hook
            if [ "$rc" != "0" ]; then
              ok=0; why="повтор: код выхода $rc"
            elif ! is_empty; then
              ok=0; why="повтор: ожидался пустой вывод"
            fi
          fi
          ;;
        *)
          ok=0; why="неизвестное ожидание $expect"
          ;;
      esac
    fi
  fi

  if [ "$ok" = "1" ]; then
    printf 'pass  %-18s %-24s %s\n' "$hook" "$fixture" "$name"
  else
    failed=$((failed + 1))
    printf 'FAIL  %-18s %-24s %s — %s\n' "$hook" "$fixture" "$name" "$why"
    [ -s "$dir/.out" ] && sed 's/^/      out: /' "$dir/.out" | head -n 3
    [ -s "$dir/.err" ] && sed 's/^/      err: /' "$dir/.err" | head -n 3
  fi
done < "$cases_file"

printf '\n%s случаев, упало %s\n' "$total" "$failed"
[ "$total" -gt 0 ] || exit 1
[ "$failed" = "0" ]
