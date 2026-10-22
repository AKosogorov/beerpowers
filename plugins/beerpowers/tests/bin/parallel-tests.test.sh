#!/bin/sh
# parallel-tests.mjs на одноразовом workspace с подменой раннера (fake-test-runner.mjs):
# раскладка по числу файлов и по junit прошлого прогона, подстановка {i}/{repo} в переменные
# воркера, исключения, резка длинной командной строки, режим native с подготовкой по слотам,
# два прогона делят слоты машины, ожидание свободного слота, уборка протухшего захвата,
# счёт упавших тестов и итоговые строки, несколько репозиториев за вызов, отказ на схеме.
#
# Запуск: sh plugins/beerpowers/tests/bin/parallel-tests.test.sh

here=$(cd -- "$(dirname -- "$0")" && pwd)
plugin=$(cd -- "$here/../.." && pwd)
tool="$plugin/templates/bin/parallel-tests.mjs"

tmp=$(mktemp -d 2>/dev/null) || tmp="${TMPDIR:-/tmp}/bp-partests-$$"
mkdir -p "$tmp" || exit 2
trap 'rm -rf "$tmp"' EXIT

# Пути внутрь JSON — в форме, которую понимает node этой системы (на Windows — C:/…).
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
runner=$(native "$here/fake-test-runner.mjs")

ws="$tmp/ws"
mkdir -p "$ws/.claude" "$ws/report" "$tmp/slots"
mkdir -p "$ws/projects/demo/.git" "$ws/projects/demo/tests/Skip" "$ws/projects/other/.git" "$ws/projects/other/tests" "$ws/projects/jsapp/.git" "$ws/projects/jsapp/tests"
printf 'cases=3 time=0.6\n' > "$ws/projects/demo/tests/AaaTest.php"
printf 'cases=2 time=0.1\n' > "$ws/projects/demo/tests/BbbTest.php"
printf 'cases=2 time=0.1\n' > "$ws/projects/demo/tests/CccTest.php"
printf 'cases=1 time=0.1\n' > "$ws/projects/demo/tests/DddTest.php"
printf 'cases=5 time=0.1\n' > "$ws/projects/demo/tests/Skip/LiveTest.php"
printf 'cases=4 time=0.1\n' > "$ws/projects/other/tests/OneTest.php"
printf 'cases=2 time=0.1\n' > "$ws/projects/jsapp/tests/a.test.js"
printf 'cases=3 time=0.1\n' > "$ws/projects/jsapp/tests/b.test.js"

write_ws() { # write_ws <команда demo>
  cat > "$ws/.claude/workspace.json" <<EOF
{
  "beerpowers": "2.3.0",
  "tests": {
    "repos": {
      "demo": {
        "command": "$1",
        "files": ["tests/**/*Test.php"],
        "exclude": ["tests/Skip"],
        "env": { "DB_NAME": "{repo}_w{i}_test", "TEST_TOKEN": "{i}", "REPORT": "{root}/report" }
      },
      "other": {
        "command": "node \"$runner\" \"{junit}\" {files}",
        "files": ["tests/*Test.php"],
        "env": { "REPORT": "{root}/report" }
      },
      "jsapp": {
        "mode": "native",
        "command": "node \"$runner\" \"{junit}\" --native {n}",
        "env": { "DB_NAME": "jsapp_w{i}_test", "REPORT": "{root}/report" },
        "prepare": "node \"$runner\" --prepare"
      }
    }
  }
}
EOF
}
write_ws "node \\\"$runner\\\" \\\"{junit}\\\" {files}"

pt() { WORKSPACE_ROOT=$(native "$ws") BEERPOWERS_TEST_SLOTS_DIR=$(native "$tmp/slots") node "$tool" "$@" 2>&1; }

total=0
failed=0
ok() { total=$((total + 1)); echo "pass  $1"; }
ko() { total=$((total + 1)); failed=$((failed + 1)); echo "FAIL  $1"; [ -n "$2" ] && printf '%s\n' "$2" | sed 's/^/      /'; }
has() { printf '%s\n' "$1" | grep -q -- "$2"; }

# 1. Раскладка без junit прошлого прогона — по числу файлов; исключённый каталог не берётся.
out=$(BEERPOWERS_TEST_SLOTS=4 pt --repos demo --workers 2 --dry-run)
if has "$out" 'по числу файлов' && has "$out" 'files=4 ' && has "$out" 'w1 slot=1 files=2' && has "$out" 'w2 slot=2 files=2' && ! has "$out" 'LiveTest'; then
  ok "без junit — по числу файлов, exclude убирает tests/Skip"
else ko "без junit — по числу файлов, exclude убирает tests/Skip" "$out"; fi

# 2. Подстановка {i} и {repo} в переменные воркера — в выводе раскладки.
if has "$out" 'env DB_NAME=demo_w1_test TEST_TOKEN=1' && has "$out" 'env DB_NAME=demo_w2_test TEST_TOKEN=2'; then
  ok "{repo} и {i} подставлены в env каждого воркера"
else ko "{repo} и {i} подставлены в env каждого воркера" "$out"; fi

# 3. Настоящий прогон: итоговые строки, переменные дошли до процесса, сводный junit записан.
rm -f "$ws/report"/*
out=$(BEERPOWERS_TEST_SLOTS=4 pt --repos demo --workers 2)
code=$?
if [ "$code" = 0 ] && has "$out" '^REPO demo .*tests=8 failed=0 .*status=ok' && has "$out" '^TOTAL repos=1 tests=8 failed=0' && [ "$(printf '%s\n' "$out" | tail -n 1)" = 'CODE=0' ]; then
  ok "прогон: REPO, TOTAL, последней строкой CODE=0"
else ko "прогон: REPO, TOTAL, последней строкой CODE=0 (код $code)" "$out"; fi
if grep -q 'db=demo_w1_test' "$ws/report/run-1.txt" 2>/dev/null && grep -q 'token=2' "$ws/report/run-2.txt" 2>/dev/null; then
  ok "переменные воркера дошли до процесса раннера"
else ko "переменные воркера дошли до процесса раннера" "$(cat "$ws/report"/* 2>&1)"; fi
cache="$ws/.claude/.cache/parallel-tests/demo.junit.xml"
if grep -q 'file="tests/AaaTest.php"' "$cache" 2>/dev/null; then
  ok "сводный junit — пути от корня репозитория"
else ko "сводный junit — пути от корня репозитория" "$(head -c 600 "$cache" 2>&1)"; fi
if [ -z "$(ls "$tmp/slots" | grep '^slot-')" ]; then ok "после прогона захваты слотов сняты"; else ko "после прогона захваты слотов сняты" "$(ls "$tmp/slots")"; fi

# 4. Раскладка по времени из junit прошлого прогона: тяжёлый файл — отдельной группой.
out=$(BEERPOWERS_TEST_SLOTS=4 pt --repos demo --workers 2 --dry-run)
if has "$out" 'по времени из junit' && has "$out" 'files=1 оценка=0.6s' && has "$out" 'files=3 оценка=0.3s'; then
  ok "по junit — жадно по времени, тяжёлый файл один в группе"
else ko "по junit — жадно по времени, тяжёлый файл один в группе" "$out"; fi

# 5. Длинная командная строка режется на несколько запусков в одном воркере.
# Каталог прогона задан явно: в имени по умолчанию стоит PID, и его длина плавает между вызовами.
len=$(BEERPOWERS_TEST_SLOTS=1 pt --repos demo --dry-run --out "$(native "$tmp/o")" | sed -n 's/.*run 1\/1 (длина \([0-9]*\) .*/\1/p')
out=$(BEERPOWERS_TEST_CMDLINE_MAX=$((len - 1)) BEERPOWERS_TEST_SLOTS=1 pt --repos demo --dry-run --out "$(native "$tmp/o")")
if [ -n "$len" ] && has "$out" 'run 1/2 ' && has "$out" 'run 2/2 '; then
  ok "команда длиннее предела — несколько запусков подряд"
else ko "команда длиннее предела — несколько запусков подряд" "$out"; fi

# 6. native: {n} — число слотов, подготовка — по разу на слот со своим {i}, тест-команда без {i}.
rm -f "$ws/report"/*
out=$(BEERPOWERS_TEST_SLOTS=4 pt --repos jsapp --workers 2)
if has "$out" '^REPO jsapp .*mode=native .*tests=5 failed=0 .*status=ok' && grep -q '^n=2$' "$ws/report/run-all.txt" 2>/dev/null \
  && grep -q 'db=jsapp_w1_test' "$ws/report/prepare-1.txt" 2>/dev/null && grep -q 'db=jsapp_w2_test' "$ws/report/prepare-2.txt" 2>/dev/null \
  && grep -q '^db=$' "$ws/report/run-all.txt" && grep -q '^slots=1,2$' "$ws/report/run-all.txt"; then
  ok "native: {n}=2, prepare по слотам, тест-команде — BEERPOWERS_TEST_SLOTS вместо {i}"
else ko "native: {n}=2, prepare по слотам, тест-команде — BEERPOWERS_TEST_SLOTS вместо {i}" "$out
$(cat "$ws/report"/* 2>&1)"; fi

# 7. Два прогона делят слоты: первый держит 2 из 3, второй получает оставшийся один.
printf 'cases=3 time=3\n' > "$ws/projects/demo/tests/AaaTest.php"
BEERPOWERS_TEST_SLOTS=3 pt --repos demo --workers 2 > "$tmp/a.out" &
apid=$!
i=0; until [ "$(ls "$tmp/slots" | grep -c '^slot-')" -ge 2 ] || [ $i -ge 100 ]; do sleep 0.1; i=$((i + 1)); done
out=$(BEERPOWERS_TEST_SLOTS=3 pt --repos other --workers 2)
wait $apid
aout=$(cat "$tmp/a.out")
if has "$aout" '^START demo .*slots=1,2 ' && has "$out" '^START other .*slots=3 ' && has "$out" 'status=ok'; then
  ok "два прогона: второй взял min(запрошено, свободно) — один слот, номер не пересёкся"
else ko "два прогона: второй взял min(запрошено, свободно) — один слот, номер не пересёкся" "$aout
---
$out"; fi

# 8. Свободных слотов нет — второй прогон ждёт и доходит до конца после первого.
BEERPOWERS_TEST_SLOTS=2 pt --repos demo --workers 2 > "$tmp/a.out" &
apid=$!
i=0; until [ "$(ls "$tmp/slots" | grep -c '^slot-')" -ge 2 ] || [ $i -ge 100 ]; do sleep 0.1; i=$((i + 1)); done
out=$(BEERPOWERS_TEST_SLOTS=2 pt --repos other)
wait $apid
if has "$out" '^WAIT other: свободных слотов нет — заняты 2 из 2' && has "$out" '^REPO other .*status=ok'; then
  ok "все слоты заняты — WAIT, затем прогон"
else ko "все слоты заняты — WAIT, затем прогон" "$out"; fi
printf 'cases=3 time=0.6\n' > "$ws/projects/demo/tests/AaaTest.php"

# 9. Протухший захват — процесс мёртв — убирается, слот достаётся новому прогону.
dead=$(node -e 'process.stdout.write(String(process.pid))')
printf '{"pid":%s,"repo":"gone"}' "$dead" > "$tmp/slots/slot-1"
out=$(BEERPOWERS_TEST_SLOTS=1 pt --repos other)
if has "$out" "^STALE slot-1 pid=$dead" && has "$out" '^START other .*slots=1 ' && has "$out" 'status=ok'; then
  ok "захват мёртвого PID убран, слот взят"
else ko "захват мёртвого PID убран, слот взят" "$out"; fi

# 10. Упавший тест: failed, строка FAIL, CODE=1.
printf 'cases=2 time=0.05 fail=1\n' > "$ws/projects/demo/tests/DddTest.php"
out=$(BEERPOWERS_TEST_SLOTS=4 pt --repos demo --workers 2)
code=$?
if [ "$code" = 1 ] && has "$out" '^REPO demo .*failed=1 .*status=fail' && has "$out" '^  FAIL DddTest.php::t0' && has "$out" '^CODE=1$'; then
  ok "упавший тест — failed=1, FAIL с именем, код 1"
else ko "упавший тест — failed=1, FAIL с именем, код 1 (код $code)" "$out"; fi
printf 'cases=1 time=0.1\n' > "$ws/projects/demo/tests/DddTest.php"

# 11. Несколько репозиториев за вызов — одновременно, TOTAL по сумме.
out=$(BEERPOWERS_TEST_SLOTS=4 pt --repos demo,other)
if has "$out" '^REPO demo ' && has "$out" '^REPO other ' && has "$out" '^TOTAL repos=2 tests=12 failed=0 .*status=ok'; then
  ok "--repos demo,other — TOTAL repos=2 tests=12"
else ko "--repos demo,other — TOTAL repos=2 tests=12" "$out"; fi

# 12. Подготовка упала — воркер в отказе, тесты не идут, код 1.
rm -f "$ws/report"/*
out=$(FAKE_PREPARE_CODE=3 BEERPOWERS_TEST_SLOTS=2 pt --repos jsapp)
code=$?
if [ "$code" = 1 ] && has "$out" 'подготовка слотов 1,2' && [ ! -f "$ws/report/run-all.txt" ]; then
  ok "prepare с ненулевым кодом — отказ, код 1"
else ko "prepare с ненулевым кодом — отказ, код 1 (код $code)" "$out"; fi

# 13. Схема: split без {files} — отказ на чтении настроек, код 2.
write_ws "node \\\"$runner\\\" \\\"{junit}\\\""
out=$(pt --repos demo --dry-run)
code=$?
if [ "$code" = 2 ] && has "$out" 'нет {files}'; then
  ok "split без {files} — отказ схемы, код 2"
else ko "split без {files} — отказ схемы, код 2 (код $code)" "$out"; fi
write_ws "node \\\"$runner\\\" \\\"{junit}\\\" {files} {i}{bogus}"
out=$(pt --repos demo --dry-run)
if has "$out" 'неизвестная подстановка {bogus}'; then
  ok "неизвестная подстановка — отказ схемы"
else ko "неизвестная подстановка — отказ схемы" "$out"; fi

# 14. Сломанный раздел tests останавливает только parallel-tests.mjs: dump для shell-скриптов
# (worktree-add, workspace-clean) идёт дальше.
out=$(node "$plugin/templates/bin/lib/workspace.mjs" dump "$(native "$ws")" 2>&1)
code=$?
if [ "$code" = 0 ] && has "$out" '^r	demo	projects/demo$'; then
  ok "сломанный tests не роняет dump остальных скриптов"
else ko "сломанный tests не роняет dump остальных скриптов (код $code)" "$out"; fi

# 15. Строка START несёт коммит прогона: свой репозиторий — head=<sha> и tree=clean|dirty,
# каталог без своего репозитория — head=? (коммит внешнего репозитория не подставляется).
write_ws "node \\\"$runner\\\" \\\"{junit}\\\" {files}"
rm -rf "$ws/projects/other/.git"
git -C "$ws/projects/other" init -q && git -C "$ws/projects/other" add -A   && git -C "$ws/projects/other" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm init
sha=$(git -C "$ws/projects/other" rev-parse HEAD)
out=$(BEERPOWERS_TEST_SLOTS=2 pt --repos other,demo)
printf 'x
' > "$ws/projects/other/new.txt"
out2=$(BEERPOWERS_TEST_SLOTS=2 pt --repos other)
if has "$out" "^START other .*head=$sha tree=clean " && has "$out" '^START demo .*head=? tree=? '   && has "$out2" "^START other .*head=$sha tree=dirty "; then
  ok "START — коммит прогона и чистота дерева, без своего репозитория — head=?"
else ko "START — коммит прогона и чистота дерева, без своего репозитория — head=?" "$out
---
$out2"; fi

echo
echo "$total случаев, упало $failed"
[ "$failed" = 0 ]
