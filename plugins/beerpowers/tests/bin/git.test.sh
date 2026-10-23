#!/bin/sh
# Git-логика скриптов .claude/bin/ на одноразовой фикстуре: два «сервера» — голые репозитории
# с веткой по умолчанию master и dev, — клоны в projects/ и копии скриптов в .claude/bin/.
# Сеть не нужна: origin — локальный путь, ls-remote отвечает с диска.
#
# Запуск: sh plugins/beerpowers/tests/bin/git.test.sh

here=$(cd -- "$(dirname -- "$0")" && pwd)
bin=$(cd -- "$here/../../templates/bin" && pwd)

tmp=$(mktemp -d 2>/dev/null) || tmp="${TMPDIR:-/tmp}/bp-git-$$"
mkdir -p "$tmp" || exit 2
trap 'rm -rf "$tmp"' EXIT

ws="$tmp/ws"
mkdir -p "$tmp/srv" "$ws/.claude/bin/lib" "$ws/projects" "$ws/memory/tasks/PROJ-1"
cp "$bin/git-base.mjs" "$bin/workspace-clean" "$bin/worktree-add" "$ws/.claude/bin/"
cp "$bin/lib/workspace.mjs" "$bin/lib/workspace.sh" "$bin/lib/git.mjs" "$ws/.claude/bin/lib/"

g() { git -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false "$@"; }

# server <имя> <ветка по умолчанию> <ветки…>: голый репозиторий с одним коммитом на всех ветках.
server() {
  name=$1 def=$2
  shift 2
  git init -q --bare "$tmp/srv/$name.git"
  seed="$tmp/seed-$name"
  git init -q "$seed"
  printf 'init\n' > "$seed/f"
  g -C "$seed" add f
  g -C "$seed" commit -q -m init
  for b in "$@"; do g -C "$seed" push -q "$tmp/srv/$name.git" "HEAD:refs/heads/$b"; done
  git -C "$tmp/srv/$name.git" symbolic-ref HEAD "refs/heads/$def"
  git clone -q "$tmp/srv/$name.git" "$ws/projects/$name"
}

server back master master release-spring
server front dev dev master

printf '%s\n' '{ "beerpowers": "2.0.0" }' > "$ws/.claude/workspace.json"
printf '%s\n' '{ "repos": { "back": "main-default", "front": "dev-default" } }' > "$ws/.claude/git-settings.json"
# Вторая таблица файла — не источник базы: её строка back не должна перекрыть первую.
printf '%s\n' '| Репозиторий | База | Выпуск |' '|---|---|---|' '| back | `release-spring` | — |' '| front | — | срочно |' \
  '' '| Шаг | Статус |' '|---|---|' '| back | MR заведён |' > "$ws/memory/tasks/PROJ-1/git-flow.md"

total=0
failed=0

# check <имя> <ожидаемый текст> <команда…>: в выводе (stdout и stderr) есть текст.
check() {
  name=$1 want=$2
  shift 2
  total=$((total + 1))
  out=$("$@" 2>&1)
  if printf '%s' "$out" | grep -qF -- "$want"; then
    echo "pass  $name"
  else
    failed=$((failed + 1))
    echo "FAIL  $name — нет «$want»"
    printf '%s\n' "$out" | sed 's/^/      /'
  fi
}

base="node $ws/.claude/bin/git-base.mjs"
lib="node $ws/.claude/bin/lib/git.mjs"

check 'main-default: база — ветка по умолчанию с сервера' 'база:     master  ← ветка по умолчанию (сервер)' $base back
check 'база из git-flow.md задачи' 'база:     release-spring' $base back PROJ-1
check 'dev-default: база dev' 'база:     dev' $base front PROJ-1
check 'dev-default: цель выпуска и срочный путь' 'master — срочно' $base front PROJ-1

g -C "$ws/projects/front" push -q origin HEAD:refs/heads/main
check 'dev-default: master и main сразу — не выбирать' 'есть и master, и main' $base front
git -C "$ws/projects/front" push -q origin --delete main

# detect: предложение профиля по веткам сервера и свежей истории.
check 'detect: master по умолчанию, линейная история — main-default' 'proposal	main-default' $lib detect "$ws" back
check 'detect: dev по умолчанию, выпуск в master — dev-default' 'proposal	dev-default' $lib detect "$ws" front
server legacy master master dev
l="$ws/projects/legacy"
g -C "$l" checkout -q -b dev origin/dev
printf 'd\n' > "$l/d"
g -C "$l" add d
g -C "$l" commit -q -m 'feat(PROJ-4): d'
g -C "$l" checkout -q master
g -C "$l" merge -q --no-ff -m "Merge branch 'dev' into 'master'" dev
g -C "$l" push -q origin master dev
check 'detect: master по умолчанию, работа приходит из dev — custom' 'proposal	custom' $lib detect "$ws" legacy
g -C "$ws/projects/front" push -q origin HEAD:refs/heads/main
check 'detect: master и main сразу — custom' 'есть и master, и main' $lib detect "$ws" front
git -C "$ws/projects/front" push -q origin --delete main
rm -rf "$l"

printf '%s\n' '{ "repos": { "back": "custom", "front": "dev-default" } }' > "$ws/.claude/git-settings.json"
check 'custom без базы в git-flow.md — отказ' 'база задачи не записана' $base back PROJ-9
printf '%s\n' '{ "repos": { "back": "main-default", "front": "dev-default" } }' > "$ws/.claude/git-settings.json"

# Влитость: перемоткой — по предкам; cherry-pick'ом — по патчу; своя работа — нет.
b="$ws/projects/back"
g -C "$b" checkout -q -b PROJ-1 origin/release-spring
printf 'x\n' >> "$b/f"
g -C "$b" commit -q -am 'feat(PROJ-1): x'
g -C "$b" push -q origin PROJ-1:release-spring
git -C "$b" fetch -q origin
check 'влита перемоткой — по предкам' 'влита	предок' $lib merged "$ws" back PROJ-1 origin/release-spring

g -C "$b" checkout -q -b PROJ-2 origin/master
printf 'y\n' > "$b/y"
g -C "$b" add y
g -C "$b" commit -q -m 'feat(PROJ-2): y'
check 'своя работа — не влита' 'невлитых коммитов: 1' $lib merged "$ws" back PROJ-2 origin/master

# master уходит вперёд: иначе cherry-pick на ту же базу дал бы тот же хеш, и сработали бы предки.
g -C "$b" checkout -q -b pick origin/master
printf 'z\n' > "$b/z"
g -C "$b" add z
g -C "$b" commit -q -m 'chore: z'
g -C "$b" cherry-pick PROJ-2 >/dev/null
g -C "$b" push -q origin pick:master
git -C "$b" fetch -q origin
check 'влита cherry-pick'"'"'ом — по патчу' 'влита	патч' $lib merged "$ws" back PROJ-2 origin/master

check 'worktree-add берёт базу из профиля' 'база origin/dev' bash "$ws/.claude/bin/worktree-add" front PROJ-7

# База голым именем ветки, которая есть только на сервере: git worktree add -b с таким именем
# заводит локальную ветку базы и выкладывает дерево на неё. Скрипт отдаёт git origin/<база>.
check 'worktree-add: база голым именем — от origin/<база>' 'база origin/release-spring' bash "$ws/.claude/bin/worktree-add" back PROJ-8 release-spring
total=$((total + 1))
on=$(git -C "$ws/worktrees/PROJ-8/back" branch --show-current)
if [ "$on" = PROJ-8 ] && ! git -C "$ws/projects/back" show-ref --verify --quiet refs/heads/release-spring; then
  echo "pass  worktree-add: дерево на ветке задачи, локальной ветки базы нет"
else failed=$((failed + 1)); echo "FAIL  worktree-add: дерево на «$on», локальная release-spring: $(git -C "$ws/projects/back" branch --list release-spring)"; fi
check 'worktree-add: базы нет нигде — отказ' 'базы «release-nope» нет' bash "$ws/.claude/bin/worktree-add" back PROJ-9 release-nope

# --copy-env после -- — флаг самого скрипта: в worktree-setup он не уходит.
printf '#!/bin/sh\necho "setup $*" > "%s/setup.log"\n' "$tmp" > "$ws/.claude/bin/worktree-setup"
chmod +x "$ws/.claude/bin/worktree-setup"
printf 'X=1\n' > "$ws/projects/back/.env"
check 'worktree-add: --copy-env после -- — свой флаг' 'скопирован .env' bash "$ws/.claude/bin/worktree-add" back PROJ-10 -- --copy-env --seed
check 'worktree-add: в worktree-setup — только флаги проекта' 'back '"$ws"'/worktrees/PROJ-10/back --seed' cat "$tmp/setup.log"
rm -f "$ws/.claude/bin/worktree-setup" "$ws/projects/back/.env"

# Дерево пересборки стенда снимается, только когда вершина отправлена в origin/<стенд>.
f="$ws/projects/front"
git -C "$f" worktree add -q --detach "$ws/worktrees/chore-dev-rebuild/front" origin/dev
printf 's\n' > "$ws/worktrees/chore-dev-rebuild/front/s"
g -C "$ws/worktrees/chore-dev-rebuild/front" add s
g -C "$ws/worktrees/chore-dev-rebuild/front" commit -q -m 'feat(PROJ-3): s'
check 'стенд не отправлен — отказ' 'не отправлена в origin/dev' bash "$ws/.claude/bin/workspace-clean" worktree chore-dev-rebuild
g -C "$ws/worktrees/chore-dev-rebuild/front" push -q origin HEAD:dev
git -C "$f" fetch -q origin
check 'стенд отправлен — снимается' 'удалил бы: worktrees/chore-dev-rebuild/front' bash "$ws/.claude/bin/workspace-clean" worktree chore-dev-rebuild

# Сухой прогон зовёт проектный teardown с --dry-run, только если тот объявил поддержку флага:
# teardown, не знающий его, выполнил бы уборку по-настоящему.
td="$ws/.claude/bin/worktree-teardown"
printf '%s\n' '#!/bin/sh' '# supports: --dry-run' 'case "$4" in --dry-run) echo "снёс бы базу test_$2" ;; *) touch "$WORKSPACE_ROOT/teardown-ran" ;; esac' > "$td"
chmod +x "$td"
check 'teardown с --dry-run: сухой прогон показывает, что снесёт' 'снёс бы базу test_front' bash "$ws/.claude/bin/workspace-clean" worktree chore-dev-rebuild
printf '%s\n' '#!/bin/sh' 'case "$4" in --dry-run) echo "снёс бы базу test_$2" ;; *) touch "$WORKSPACE_ROOT/teardown-ran" ;; esac' > "$td"
total=$((total + 1))
out=$(bash "$ws/.claude/bin/workspace-clean" worktree chore-dev-rebuild 2>&1)
if printf '%s' "$out" | grep -qF 'вызвал бы: .claude/bin/worktree-teardown' && [ ! -e "$ws/teardown-ran" ]; then
  echo "pass  teardown без объявления: сухой прогон только называет его"
else
  failed=$((failed + 1)); echo "FAIL  teardown без объявления вызван в сухом прогоне"; printf '%s\n' "$out" | sed 's/^/      /'
fi
rm -f "$td"

# Пропажи при перезаписи стенда: git-base --lost и барьер guard-push считают одинаково.
# Прежний стенд stage: A — коммит задачи, B — правка прямо на стенде, C — коммит, который
# в новом стенде правлен на конфликте. Новый стенд собран от ушедшего вперёд dev: A перенесён
# cherry-pick'ом (другой хеш, тот же патч), C — с той же темой и другим патчем, B выпал.
commit() { printf '%s\n' "$2" > "$f/$1"; g -C "$f" add "$1"; g -C "$f" commit -q -m "$3"; }
g -C "$f" checkout -q -b stage origin/dev
commit a a 'feat(PROJ-5): a'
commit b b 'chore: правка на стенде'
commit c c 'feat(PROJ-6): c'
g -C "$f" push -q origin stage
g -C "$f" checkout -q -b dev-next origin/dev
commit d d 'feat(PROJ-8): d'
g -C "$f" push -q origin dev-next:dev
g -C "$f" checkout -q -b stage-new dev-next
g -C "$f" cherry-pick stage~2 >/dev/null
commit c c2 'feat(PROJ-6): c'
git -C "$f" fetch -q origin
check 'lost: правка на стенде выпала' 'chore: правка на стенде' $base --lost projects/front origin/stage stage-new
check 'lost: перенесённое и правленое не в счёт' 'пропадёт: 1 ' $base --lost projects/front origin/stage stage-new
check 'lost: перемотка — пропаж нет' 'пропадёт: ничего' $base --lost projects/front origin/dev stage-new

hook="$here/../../hooks/guard-push.sh"
printf '# charter\n' > "$ws/.claude/team-charter.md"
push_event() {
  printf '{"tool_name":"Bash","tool_input":{"command":"git -C %s push --force-with-lease origin %s"}}' "$f" "$1" \
    | CLAUDE_PROJECT_DIR="$ws" sh "$hook"
}
# Ответ хука разбирается как JSON: тема коммита попадает в него строкой и не должна его ломать.
deny_reason() {
  push_event "$1" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const o=JSON.parse(s).hookSpecificOutput;console.log(o.permissionDecision, o.permissionDecisionReason)})'
}
check 'guard-push: push с силой теряет коммит — отказ со списком' 'deny После этого push из origin/stage пропадут коммиты (1)' deny_reason stage-new:stage
rm -f "$ws/.claude/.cache/push-lost"
check 'guard-push: в списке — выпавший коммит' 'chore: правка на стенде' deny_reason stage-new:stage
total=$((total + 1))
if [ -z "$(push_event stage-new:stage)" ]; then echo "pass  guard-push: та же пара вершин второй раз проходит"
else failed=$((failed + 1)); echo "FAIL  guard-push: повтор той же пары заблокирован"; fi
g -C "$f" cherry-pick stage~1 >/dev/null
total=$((total + 1))
if [ -z "$(push_event stage-new:stage)" ]; then echo "pass  guard-push: ничего не пропадает — проходит"
else failed=$((failed + 1)); echo "FAIL  guard-push: отказ без пропаж"; fi

# worktree-add ставит зависимости сам, по lock-файлу; pnpm и composer подменены заглушками.
stubs="$tmp/stubs"
mkdir -p "$stubs"
for t in pnpm npm composer; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/deps.log"\n' "$t" "$tmp" > "$stubs/$t"
  chmod +x "$stubs/$t"
done
g -C "$b" checkout -q -b locks origin/master
printf '{}\n' > "$b/package.json"
printf 'lockfileVersion: 9\n' > "$b/pnpm-lock.yaml"
printf '{}\n' > "$b/composer.lock"
g -C "$b" add package.json pnpm-lock.yaml composer.lock
g -C "$b" commit -q -m 'chore: lock-файлы'
g -C "$b" push -q origin locks:master
git -C "$b" fetch -q origin
: > "$tmp/deps.log"
PATH="$stubs:$PATH" bash "$ws/.claude/bin/worktree-add" back PROJ-12 >/dev/null 2>&1
check 'worktree-add: pnpm по pnpm-lock.yaml без флагов' 'install --frozen-lockfile' cat "$tmp/deps.log"
check 'worktree-add: composer по composer.lock' 'composer install --working-dir=' cat "$tmp/deps.log"
: > "$tmp/deps.log"
PATH="$stubs:$PATH" bash "$ws/.claude/bin/worktree-add" back PROJ-13 --no-deps >/dev/null 2>&1
total=$((total + 1))
if [ -s "$tmp/deps.log" ]; then failed=$((failed + 1)); echo "FAIL  worktree-add --no-deps всё равно ставил зависимости"; else echo "pass  worktree-add --no-deps: зависимости не ставятся"; fi

# Техдолг в workspace с несколькими репозиториями: поле repo обязательно и сверяется с projects/.
cp "$bin/tech-debt-index.mjs" "$ws/.claude/bin/"
td_dir="$ws/memory/tech-debt"
mkdir -p "$td_dir"
td_item() { printf '%s\n' '---' 'status: открыт' 'area: корзина' 'checked: 2026-10-17' "$2" '---' '' '# 1. Пункт' > "$td_dir/001-x.md"; }
td_item x ''
check 'техдолг: без repo при нескольких репозиториях — отказ' 'нет repo' node "$ws/.claude/bin/tech-debt-index.mjs"
td_item x 'repo: bakc'
check 'техдолг: repo не из projects/ — отказ' 'repo «bakc»' node "$ws/.claude/bin/tech-debt-index.mjs"
td_item x 'repo: back, workspace'
node "$ws/.claude/bin/tech-debt-index.mjs" >/dev/null 2>&1
check 'техдолг: колонка «Репозиторий» в индексе' '| 1 | открыт | корзина | back, workspace |' cat "$td_dir/tech-debt.md"

echo
echo "$total случаев, упало $failed"
[ "$failed" = 0 ]
