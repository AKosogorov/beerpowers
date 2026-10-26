#!/bin/sh
# workspace-clean cache на одноразовом workspace: копия мутантов на свободном слоте и на слоте,
# который держит живой прогон mutants; прогоны parallel-tests старше порога, свежий и с живым pid;
# состояние напоминания о скриншотах; junit, состояние барьера и чужой файл в корне кеша.
# Сухой прогон ничего не удаляет, --apply удаляет только своё и снимает регистрацию worktree.
#
# Запуск: sh plugins/beerpowers/tests/bin/workspace-clean.test.sh

here=$(cd -- "$(dirname -- "$0")" && pwd)
bin=$(cd -- "$here/../../templates/bin" && pwd)

tmp=$(mktemp -d 2>/dev/null) || tmp="${TMPDIR:-/tmp}/bp-wsclean-$$"
mkdir -p "$tmp" || exit 2
sleeper=""
trap '[ -n "$sleeper" ] && kill "$sleeper" 2>/dev/null; rm -rf "$tmp"' EXIT

native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

ws="$tmp/ws"
base="$ws/projects/calc"
cache="$ws/.claude/.cache"
mkdir -p "$ws/.claude/bin/lib" "$tmp/slots" "$base"
cp "$bin/workspace-clean" "$bin/mutants.mjs" "$ws/.claude/bin/"
cp "$bin/lib/workspace.mjs" "$bin/lib/workspace.sh" "$bin/lib/git.mjs" "$bin/lib/slots.mjs" "$ws/.claude/bin/lib/"
printf '%s\n' '{ "beerpowers": "2.12.0" }' > "$ws/.claude/workspace.json"

printf 'init\n' > "$base/f"
git -C "$base" init -q
git -C "$base" add -A
git -C "$base" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m init
mkdir -p "$cache/mutants"
git -C "$base" worktree add -q --detach "$cache/mutants/calc-s1"
git -C "$base" worktree add -q --detach "$cache/mutants/calc-s2"

# Живой процесс с системным pid: им «держится» слот 2 и «идёт» прогон.
node -e 'require("fs").writeFileSync(process.argv[1], String(process.pid)); setTimeout(() => {}, 120000)' "$(native "$tmp/pid")" &
sleeper=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$tmp/pid" ] && break; sleep 1; done
pid=$(cat "$tmp/pid")
printf '{"pid":%s,"tool":"mutants","since":"2026-10-26T00:00:00Z"}' "$pid" > "$tmp/slots/slot-2"

runs="$cache/parallel-tests/runs"
mkdir -p "$runs/20200101-000000-999999" "$runs/20200101-000000-$pid" "$runs/20991231-000000-999998" "$runs/stray"
printf 'log\n' > "$runs/20200101-000000-999999/w1.log"
printf 'log\n' > "$runs/20200101-000000-$pid/w1.log"
printf '<testsuites/>\n' > "$cache/parallel-tests/demo.junit.xml"
mkdir -p "$cache/screenshots-reminder/old-session" "$cache/screenshots-reminder/new-session"
: > "$cache/screenshots-reminder/old-session/agent-1"
printf 'fp' > "$cache/comment-guard"
printf 'mine\n' > "$cache/notes.txt"
touch -t 202001010000 "$runs/20200101-000000-999999" "$runs/20200101-000000-$pid" "$runs/stray" "$cache/screenshots-reminder/old-session"

wc_() { WORKSPACE_ROOT=$(native "$ws") BEERPOWERS_TEST_SLOTS_DIR=$(native "$tmp/slots") bash "$ws/.claude/bin/workspace-clean" "$@" 2>&1; }

total=0
failed=0
ok() { total=$((total + 1)); echo "pass  $1"; }
ko() { total=$((total + 1)); failed=$((failed + 1)); echo "FAIL  $1"; [ -n "$2" ] && printf '%s\n' "$2" | sed 's/^/      /'; }
has() { printf '%s\n' "$1" | grep -qF -- "$2"; }
all_there() {
  [ -d "$cache/mutants/calc-s1" ] && [ -d "$cache/mutants/calc-s2" ] && [ -d "$runs/20200101-000000-999999" ] \
    && [ -d "$runs/20200101-000000-$pid" ] && [ -d "$runs/20991231-000000-999998" ] && [ -d "$cache/screenshots-reminder/old-session" ]
}

# 1. Сухой прогон: каждая позиция с причиной, ничего не удалено.
out=$(wc_ cache)
code=$?
if [ "$code" = 0 ] && all_there && has "$out" 'удалил бы: .claude/.cache/mutants/calc-s1' \
  && has "$out" "занята: .claude/.cache/mutants/calc-s2 — слот держит pid $pid" \
  && has "$out" 'удалил бы: .claude/.cache/parallel-tests/runs/20200101-000000-999999' \
  && has "$out" "идёт: .claude/.cache/parallel-tests/runs/20200101-000000-$pid — pid $pid жив" \
  && has "$out" 'не трогаю: .claude/.cache/parallel-tests/runs/stray — имя не в форме' \
  && has "$out" 'не трогаю: .claude/.cache/parallel-tests/*.junit.xml' \
  && has "$out" 'удалил бы: .claude/.cache/screenshots-reminder/old-session' \
  && has "$out" 'не трогаю: состояние барьеров и команд — comment-guard' \
  && has "$out" 'не моё, не трогаю: notes.txt' \
  && has "$out" 'итог: копий мутантов убрал бы 1 (заняты прогоном: 1), прогонов тестов убрал бы 1 (идут: 1, моложе 7 дн.: 1), каталогов состояния убрал бы 1' \
  && ! has "$out" 'new-session' && ! has "$out" '20991231'; then
  ok "сухой прогон — позиции с причинами, ничего не удалено"
else ko "сухой прогон — позиции с причинами, ничего не удалено (код $code)" "$out"; fi

# 2. Флаги: цель у cache и --keep-days у другого режима — отказ.
out=$(wc_ cache extra)
if [ $? != 0 ] && has "$out" 'у cache нет цели'; then ok "cache с целью — отказ"; else ko "cache с целью — отказ" "$out"; fi
out=$(wc_ output --keep-days 3)
if [ $? != 0 ] && has "$out" '--keep-days — только у cache'; then ok "--keep-days не у cache — отказ"; else ko "--keep-days не у cache — отказ" "$out"; fi
out=$(wc_ cache --keep-days x)
if [ $? != 0 ] && has "$out" 'ждётся целое число дней'; then ok "--keep-days не число — отказ"; else ko "--keep-days не число — отказ" "$out"; fi

# 3. --apply: только свободная копия, старый мёртвый прогон и старое состояние.
out=$(wc_ cache --apply)
code=$?
if [ "$code" = 0 ] && [ ! -e "$cache/mutants/calc-s1" ] && [ -d "$cache/mutants/calc-s2" ] \
  && [ ! -e "$runs/20200101-000000-999999" ] && [ -d "$runs/20200101-000000-$pid" ] && [ -d "$runs/20991231-000000-999998" ] && [ -d "$runs/stray" ] \
  && [ ! -e "$cache/screenshots-reminder/old-session" ] && [ -d "$cache/screenshots-reminder/new-session" ] \
  && [ -f "$cache/parallel-tests/demo.junit.xml" ] && [ -f "$cache/comment-guard" ] && [ -f "$cache/notes.txt" ] \
  && has "$out" 'итог: копий мутантов убрано 1 (заняты прогоном: 1), прогонов тестов убрано 1'; then
  ok "--apply — убрано только своё, занятое и чужое на месте"
else ko "--apply — убрано только своё, занятое и чужое на месте (код $code)" "$out
$(ls -R "$cache" 2>&1)"; fi

# 4. Регистрация убранной копии снята, занятая осталась.
wl=$(git -C "$base" worktree list --porcelain)
if ! printf '%s\n' "$wl" | grep -q 'mutants/calc-s1' && printf '%s\n' "$wl" | grep -q 'mutants/calc-s2'; then
  ok "git worktree list — без убранной копии, занятая на месте"
else ko "git worktree list — без убранной копии, занятая на месте" "$wl"; fi

# 5. Прогон закончился: слот свободен, pid мёртв — уходят и копия, и прогон.
kill "$sleeper" 2>/dev/null
wait "$sleeper" 2>/dev/null
sleeper=""
out=$(wc_ cache --apply)
if [ ! -e "$cache/mutants/calc-s2" ] && [ ! -e "$runs/20200101-000000-$pid" ] && [ -d "$runs/20991231-000000-999998" ] \
  && [ -z "$(git -C "$base" worktree list --porcelain | grep 'mutants')" ]; then
  ok "после прогона — копия и прогон убраны"
else ko "после прогона — копия и прогон убраны" "$out"; fi

# 6. --keep-days 0 — уходит и свежий прогон.
out=$(wc_ cache --keep-days 0 --apply)
if [ ! -e "$runs/20991231-000000-999998" ] && [ ! -e "$cache/screenshots-reminder/new-session" ] && [ -d "$runs/stray" ]; then
  ok "--keep-days 0 — свежие тоже убраны, чужое имя на месте"
else ko "--keep-days 0 — свежие тоже убраны, чужое имя на месте" "$out"; fi

# 7. Каталог кеша — символьная ссылка: отказ, по ссылке не ходит.
mkdir -p "$tmp/outside/runs/20200101-000000-1"
touch -t 202001010000 "$tmp/outside/runs/20200101-000000-1"
rm -rf "$runs"
if ln -s "$tmp/outside/runs" "$runs" 2>/dev/null && [ -L "$runs" ]; then
  out=$(wc_ cache --apply)
  if [ $? != 0 ] && has "$out" 'символьная ссылка' && [ -d "$tmp/outside/runs/20200101-000000-1" ]; then
    ok "кеш по символьной ссылке — отказ, снаружи цело"
  else ko "кеш по символьной ссылке — отказ, снаружи цело" "$out"; fi
else
  echo "skip  кеш по символьной ссылке — ln -s здесь не создаёт ссылку"
fi

echo
echo "$total случаев, упало $failed"
[ "$failed" = 0 ]
