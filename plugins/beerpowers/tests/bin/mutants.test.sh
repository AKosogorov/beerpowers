#!/bin/sh
# mutants.mjs на одноразовом workspace с настоящим git-репозиторием и подменой теста
# (fake-mutant-test.mjs): убит и выжил, ровно одно вхождение find, база не тронута, копии чистые,
# два потока на разных копиях, ссылка и копия файлов в копии, кеш по хешу, незакоммиченные
# правки базы в копии, нулевой мутант, мусор теста в копии, --only, --dry-run, --clean не трогает
# vendor базы, vendor composer в копии, проверка копии пустым файлом, настоящий PHP (если есть), отказ схемы.
#
# Запуск: sh plugins/beerpowers/tests/bin/mutants.test.sh

here=$(cd -- "$(dirname -- "$0")" && pwd)
plugin=$(cd -- "$here/../.." && pwd)
tool="$plugin/templates/bin/mutants.mjs"

tmp=$(mktemp -d 2>/dev/null) || tmp="${TMPDIR:-/tmp}/bp-mutants-$$"
mkdir -p "$tmp" || exit 2
trap 'rm -rf "$tmp"' EXIT

native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
runner=$(native "$here/fake-mutant-test.mjs")

ws="$tmp/ws"
base="$ws/projects/calc"
mkdir -p "$ws/.claude" "$ws/report" "$tmp/slots" "$tmp/scratch" "$base/src" "$base/tests" "$base/vendor"
printf 'limit<=90\nextra=1\ndup=x\ndup=x\n' > "$base/src/rule.txt"
printf 'expect limit<=90\n' > "$base/tests/rule.test"
printf 'vendor/\n.env.testing\n' > "$base/.gitignore"
printf 'marker\n' > "$base/vendor/marker"
printf 'APP_ENV=testing\n' > "$base/.env.testing"
git -C "$base" init -q
git -C "$base" add -A
git -C "$base" -c user.name=t -c user.email=t@t commit -q -m init

write_ws() { # write_ws <mutate.command>
  cat > "$ws/.claude/workspace.json" <<EOF
{
  "beerpowers": "2.4.0",
  "tests": {
    "repos": {
      "calc": {
        "command": "node \"$runner\" {files}",
        "files": ["tests/*.test"],
        "env": { "DB_NAME": "calc_w{i}_test", "REPORT": "{root}/report" },
        "mutate": { "command": "$1", "link": ["vendor"], "copy": [".env.testing"] }
      },
      "phpapp": {
        "command": "php {files}",
        "files": ["tests/*Test.php"],
        "mutate": { "command": "php {filter}", "link": ["vendor"] }
      }
    }
  }
}
EOF
}
write_ws "node \\\"$runner\\\" {filter}"

muts="$tmp/scratch/mutants.json"
cat > "$muts" <<'EOF'
{
  "repo": "calc",
  "filter": "tests/rule.test",
  "tests": ["tests/rule.test:1"],
  "mutants": [
    { "id": "M1", "criterion": "граница включительно", "file": "src/rule.txt", "find": "limit<=90", "replace": "limit<90", "what": "<= на <" },
    { "id": "M2", "criterion": "extra по умолчанию 1", "file": "src/rule.txt", "find": "extra=1", "replace": "extra=2" },
    { "id": "M3", "file": "src/rule.txt", "find": "dup=x", "replace": "dup=y" },
    { "id": "M4", "file": "src/rule.txt", "find": "nothere", "replace": "x" }
  ]
}
EOF

mt() { WORKSPACE_ROOT=$(native "$ws") BEERPOWERS_TEST_SLOTS_DIR=$(native "$tmp/slots") BEERPOWERS_TEST_SLOTS=4 node "$tool" "$@" 2>&1; }

total=0
failed=0
ok() { total=$((total + 1)); echo "pass  $1"; }
ko() { total=$((total + 1)); failed=$((failed + 1)); echo "FAIL  $1"; [ -n "$2" ] && printf '%s\n' "$2" | sed 's/^/      /'; }
has() { printf '%s\n' "$1" | grep -q -- "$2"; }
copies_clean() {
  for c in "$ws/.claude/.cache/mutants"/*; do
    [ -d "$c" ] || continue
    # Ссылка и копия файла — не изменения копии, как и у инструмента: «vendor/» симлинк не ловит.
    [ -z "$(git -C "$c" status --porcelain -- . ':(exclude)vendor' ':(exclude).env.testing')" ] || return 1
  done
}

before=$(git -C "$base" status --porcelain; cat "$base/src/rule.txt")

# 1. Первый прогон: убит, выжил, две ошибки применения; таблица; CODE=1 из-за выжившего.
out=$(FAKE_SLEEP_MS=600 mt "$(native "$muts")" --workers 2)
code=$?
if [ "$code" = 1 ] && has "$out" '^done control-1 (M1,M2) зелёный' && has "$out" '| `M1` <= на < (`src/rule.txt`) | зелёный | красный | убит |' \
  && has "$out" '`M2` .* | зелёный | зелёный | выжил |' && has "$out" 'M3` .*ошибка применения: find встречается в src/rule.txt 2 раз' \
  && has "$out" 'M4` .*ошибка применения: find встречается в src/rule.txt 0 раз' \
  && has "$out" '^TOTAL mutants=4 killed=1 survived=1 errors=2 ' && [ -f "$tmp/scratch/mutants.table.md" ]; then
  ok "убит, выжил, ровно одно вхождение find, таблица файлом, CODE=1"
else ko "убит, выжил, ровно одно вхождение find, таблица файлом, CODE=1 (код $code)" "$out"; fi

# 2. База не тронута, копии после отката чистые.
if [ "$(git -C "$base" status --porcelain; cat "$base/src/rule.txt")" = "$before" ] && copies_clean; then
  ok "база не тронута, git status копий пуст"
else ko "база не тронута, git status копий пуст" "$(git -C "$base" status --porcelain)"; fi

# 3. Два потока — на двух разных копиях со своими базами; ссылка и копия файла на месте.
dirs=$(cat "$ws/report"/s*.txt 2>/dev/null | sed 's/ db=.*//' | sort -u | wc -l | tr -d ' ')
if [ "$dirs" = 2 ] && grep -q 'db=calc_w1_test' "$ws/report/s1.txt" && grep -q 'db=calc_w2_test' "$ws/report/s2.txt"; then
  ok "два слота — две копии, база по {i}"
else ko "два слота — две копии, база по {i}" "$(cat "$ws/report"/* 2>&1)"; fi

# 4. Повтор без изменений — всё из кеша, слоты не берутся.
out=$(mt "$(native "$muts")")
if ! has "$out" '^START' && has "$out" '| убит (кеш) |' && has "$out" '| выжил (кеш) |' && has "$out" ' cached=2 '; then
  ok "без изменений — результат из кеша по хешу"
else ko "без изменений — результат из кеша по хешу" "$out"; fi

# 5. Незакоммиченная правка теста в базе: хеш сменился, мутанты перезапущены в копии с правкой.
printf 'expect limit<=90\nexpect extra=1\n' > "$base/tests/rule.test"
out=$(mt "$(native "$muts")")
if has "$out" '^START mutants=2 ' && has "$out" '`M2` .* | зелёный | красный | убит |' && ! has "$out" '(кеш)'; then
  ok "правка теста без коммита — изменившиеся перезапущены, выживший убит"
else ko "правка теста без коммита — изменившиеся перезапущены, выживший убит" "$out"; fi

# 6. Нулевой мутант красный — мутанты его фильтра недействительны, красное не кешируется.
printf 'expect limit<=90\nexpect missing=1\n' > "$base/tests/rule.test"
out=$(mt "$(native "$muts")")
code=$?
if [ "$code" = 1 ] && has "$out" '^done control-1 (M1,M2) красный' && has "$out" 'недействителен: контроль control-1 красный' && has "$out" ' invalid=2 '; then
  out2=$(mt "$(native "$muts")" --dry-run)
  if has "$out2" '^control-1 .* — прогон'; then ok "нулевой мутант красный — недействителен, контроль не из кеша"
  else ko "нулевой мутант красный — недействителен, контроль не из кеша" "$out2"; fi
else ko "нулевой мутант красный — недействителен, контроль не из кеша (код $code)" "$out"; fi
printf 'expect limit<=90\nexpect extra=1\n' > "$base/tests/rule.test"

# 7. Тест оставил мусор в копии — копия восстановлена, результат в силе.
out=$(FAKE_LITTER=1 mt "$(native "$muts")" --force --only M1)
if has "$out" '`M1` .*| убит |' && copies_clean && grep -q 'копия не чистая после отката: junk.txt' "$tmp/scratch/mutants.runs/M1.log"; then
  ok "мусор теста убран, копия чистая; --only гоняет только названный"
else ko "мусор теста убран, копия чистая; --only гоняет только названный" "$out"; fi
if ! has "$out" 'done M2'; then ok "--only M1 — M2 не прогонялся"; else ko "--only M1 — M2 не прогонялся" "$out"; fi

# 8. --dry-run — план без прогона.
out=$(mt "$(native "$muts")" --dry-run)
if has "$out" '^M3 calc src/rule.txt — ошибка применения' && has "$out" '^план: '; then
  ok "--dry-run — план"
else ko "--dry-run — план" "$out"; fi

# 9. --clean убирает копии, vendor базы цел (ссылка снята до удаления дерева).
out=$(mt --clean)
if has "$out" 'копий убрано: 2' && [ -f "$base/vendor/marker" ] && [ -z "$(ls "$ws/.claude/.cache/mutants" 2>/dev/null)" ] && [ -z "$(git -C "$base" worktree list --porcelain | grep 'mutants')" ]; then
  ok "--clean — копии убраны, vendor базы на месте, worktree сняты"
else ko "--clean — копии убраны, vendor базы на месте, worktree сняты" "$out
$(git -C "$base" worktree list)"; fi

# 11. vendor в раскладке composer: копия получает настоящий каталог vendor — composer/, bin/
# и файлы верхнего уровня копией, пакеты ссылками; код ищется от реального пути vendor/composer.
mkdir -p "$base/vendor/composer" "$base/vendor/pkg" "$base/vendor/bin"
printf 'map\n' > "$base/vendor/composer/autoload_psr4.txt"
printf 'autoload\n' > "$base/vendor/autoload.php"
printf 'lib\n' > "$base/vendor/pkg/lib.txt"
printf 'proxy\n' > "$base/vendor/bin/tool"
out=$(FAKE_COMPOSER=1 mt "$(native "$muts")" --force)
c1="$ws/.claude/.cache/mutants/calc-s1"
if has "$out" '`M1` .*| зелёный | красный | убит |' && has "$out" '`M2` .*| зелёный | красный | убит |' \
  && [ -d "$c1/vendor" ] && [ ! -L "$c1/vendor" ] && [ ! -L "$c1/vendor/composer" ] && [ ! -L "$c1/vendor/bin" ] \
  && [ -L "$c1/vendor/pkg" ] && [ -f "$c1/vendor/autoload.php" ] && copies_clean; then
  ok "vendor composer: composer/ и bin/ копией, пакеты ссылкой — мутанты видны тесту"
else ko "vendor composer: composer/ и bin/ копией, пакеты ссылкой — мутанты видны тесту" "$out
$(ls -la "$c1/vendor" 2>&1)"; fi

# 12. Тест читает код не из копии — проверка копии (файл опустошён, фильтр зелёный) делает
# мутанты недействительными, а не выжившими. Копии переиспользуются: их vendor пересобирается,
# vendor базы обязан остаться целым.
out=$(FAKE_SRC_DIR=$(native "$base") mt "$(native "$muts")" --force)
code=$?
if [ "$code" = 1 ] && has "$out" '^done copycheck-1 (src/rule.txt: M1,M2) зелёный' \
  && has "$out" '`M1` .*недействителен: тест не видит src/rule.txt копии' && ! has "$out" '| выжил' && has "$out" ' invalid=2 ' \
  && [ -f "$base/vendor/pkg/lib.txt" ] && [ -f "$base/vendor/composer/autoload_psr4.txt" ] && [ -f "$base/vendor/bin/tool" ]; then
  ok "тест не видит копию — проверка копии, мутанты недействительны"
else ko "тест не видит копию — проверка копии, мутанты недействительны (код $code)" "$out"; fi

# 13. Настоящий PHP с автозагрузчиком composer ($baseDir = dirname($vendorDir) от __DIR__):
# мутант обязан быть убит. Без php на машине — пропуск.
if command -v php >/dev/null 2>&1; then
  pb="$ws/projects/phpapp"
  mkdir -p "$pb/app" "$pb/tests" "$pb/vendor/composer"
  printf '<?php\nnamespace App;\nclass Rule { public static function limit(): int { return 90; } }\n' > "$pb/app/Rule.php"
  printf '<?php\nrequire "vendor/autoload.php";\nexit(App\\Rule::limit() === 90 ? 0 : 1);\n' > "$pb/tests/RuleTest.php"
  cat > "$pb/vendor/composer/autoload_psr4.php" <<'PHP'
<?php
$vendorDir = dirname(__DIR__);
$baseDir = dirname($vendorDir);
return ['App\\' => [$baseDir . '/app']];
PHP
  cat > "$pb/vendor/autoload.php" <<'PHP'
<?php
$map = require __DIR__ . '/composer/autoload_psr4.php';
spl_autoload_register(function ($class) use ($map) {
    foreach ($map as $prefix => $dirs) {
        if (strpos($class, $prefix) !== 0) continue;
        foreach ($dirs as $dir) {
            $file = $dir . '/' . str_replace('\\', '/', substr($class, strlen($prefix))) . '.php';
            if (is_file($file)) { require $file; return; }
        }
    }
});
PHP
  printf 'vendor/\n' > "$pb/.gitignore"
  git -C "$pb" init -q && git -C "$pb" add -A && git -C "$pb" -c user.name=t -c user.email=t@t commit -q -m init
  cat > "$tmp/scratch/php.json" <<'EOF'
{ "repo": "phpapp", "filter": "tests/RuleTest.php", "tests": ["tests/RuleTest.php:3"],
  "mutants": [ { "id": "M1", "file": "app/Rule.php", "find": "return 90;", "replace": "return 91;" } ] }
EOF
  out=$(mt "$(native "$tmp/scratch/php.json")")
  code=$?
  if [ "$code" = 0 ] && has "$out" '^done copycheck-1 (app/Rule.php: M1) красный' && has "$out" '`M1` .*| зелёный | красный | убит |'; then
    ok "настоящий PHP и автозагрузчик composer — мутант убит в копии"
  else ko "настоящий PHP и автозагрузчик composer — мутант убит в копии (код $code)" "$out"; fi
else
  echo "skip  настоящий PHP и автозагрузчик composer — php на машине нет"
fi

# 10. Схема: mutate.command без {filter} — отказ, код 2.
write_ws "node \\\"$runner\\\" tests/rule.test"
out=$(mt "$(native "$muts")")
code=$?
if [ "$code" = 2 ] && has "$out" 'нет {filter}'; then ok "mutate.command без {filter} — отказ схемы"; else ko "mutate.command без {filter} — отказ схемы (код $code)" "$out"; fi

echo
echo "$total случаев, упало $failed"
[ "$failed" = 0 ]
