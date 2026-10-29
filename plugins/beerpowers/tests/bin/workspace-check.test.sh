#!/bin/sh
# workspace-check, проверка «ссылки на файлы памяти и .claude не битые»: ссылка на файл, который
# создаст команда плагина позже (`memory/decisions.md` — feature, `memory/product-*.md` —
# product-onboard), пока его нет, не битая; ссылка на отсутствующий файл вне этого списка — битая.
# Роль `product` из шаблона ссылается на оба вида внутри engine-блоков, и setup с PM-дорожкой
# иначе не может получить зелёный workspace-check.
#
# Запуск: sh plugins/beerpowers/tests/bin/workspace-check.test.sh

here=$(cd -- "$(dirname -- "$0")" && pwd)
plugin=$(cd -- "$here/../.." && pwd)
check="$plugin/templates/bin/workspace-check.mjs"

tmp=$(mktemp -d 2>/dev/null) || tmp="${TMPDIR:-/tmp}/bp-wscheck-$$"
mkdir -p "$tmp" || exit 2
trap 'rm -rf "$tmp"' EXIT

total=0
failed=0
ok() { total=$((total + 1)); echo "pass  $1"; }
ko() { total=$((total + 1)); failed=$((failed + 1)); echo "FAIL  $1"; [ -n "$2" ] && printf '%s\n' "$2" | sed 's/^/      /'; }

# Вывод проверки ссылок: её строка PASS/FAIL и строки находок под ней.
links() {
  WORKSPACE_ROOT="$tmp/ws" node "$check" 2>&1 | awk '
    /^(PASS|FAIL)  / { on = ($0 ~ /ссылки на файлы памяти/) }
    on'
}

# Workspace сразу после setup — golden-эталон с копиями скриптов (в эталон они не входят,
# а копии reference на них ссылаются). Роли product в эталоне нет — кладём её из шаблона.
repo=$(cd -- "$plugin/../.." && pwd)
cp -R "$repo/examples/laravel-nuxt" "$tmp/ws"
mkdir -p "$tmp/ws/.claude/bin"
cp -R "$plugin/templates/bin/." "$tmp/ws/.claude/bin/"

out=$(links)
case "$out" in
  PASS*) ok "эталон без роли product — ссылки целы" ;;
  *) ko "эталон без роли product — ссылки целы" "$out" ;;
esac

# Схема барьеров в lib/workspace.mjs знает каждый барьер эталона: ключ, который миграция велит
# записать в workspace.json, иначе роняет проверку «ключи и типы».
out=$(WORKSPACE_ROOT="$tmp/ws" node "$check" 2>&1 | grep 'неизвестный барьер')
if [ -z "$out" ]; then ok "барьеры эталона известны схеме workspace.json"
else ko "барьеры эталона известны схеме workspace.json" "$out"; fi

cp "$plugin/templates/roles/product-agent.md" "$tmp/ws/.claude/agents/product-agent.md"

out=$(links)
case "$out" in
  PASS*) ok "роль product из шаблона без memory/decisions.md и memory/product-*.md" ;;
  *) ko "роль product из шаблона без memory/decisions.md и memory/product-*.md" "$out" ;;
esac

printf '%s\n' 'Правило — в `memory/project/nope.md`.' > "$tmp/ws/memory/project/broken.md"
out=$(links)
case "$out" in
  FAIL*memory/project/nope.md*) ok "ссылка на отсутствующий memory/project/nope.md — битая" ;;
  *) ko "ссылка на отсутствующий memory/project/nope.md — битая" "$out" ;;
esac

printf '%s\n' 'Опечатка — `memory/product-actros.md`.' > "$tmp/ws/memory/project/broken.md"
out=$(links)
case "$out" in
  FAIL*memory/product-actros.md*) ok "имя не из списка команд плагина — битая, даже с префиксом product-" ;;
  *) ko "имя не из списка команд плагина — битая, даже с префиксом product-" "$out" ;;
esac

# Правило без снимка состояния кода — проверка warn: ловит снимок в правиле, молчит в наблюдении,
# в блоке кода, в разделе «Грабли» и в строке с датой; код выхода от неё не меняется.
rm -f "$tmp/ws/memory/project/broken.md"
snap() {
  WORKSPACE_ROOT="$tmp/ws" node "$check" 2>&1 | awk '
    /^(PASS|FAIL|WARN)  / { on = ($0 ~ /снимков состояния кода/) }
    on'
}
expect() { # <имя> <образец вывода: WARN-строка с путём:строкой или PASS>
  out=$(snap)
  if printf '%s\n' "$out" | grep -qF -- "$2"; then ok "$1"; else ko "$1" "$out"; fi
}
rules="$tmp/ws/.claude/rules/snap.md"
cat > "$rules" <<'EOF'
---
paths: ["projects/*/app/**"]
---

- Тип проверяет `typescript.typeCheck` в `nuxt.config.ts`.
EOF
expect "правило без снимка — тихо" "PASS  в правилах нет снимков"

printf '%s\n' '- `nuxt.config.ts:68` включает проверку типов.' >> "$rules"
expect "номер строки в правиле — warn с путём и строкой" ".claude/rules/snap.md:6 номер строки"
code=0; WORKSPACE_ROOT="$tmp/ws" node "$check" > "$tmp/wc.out" 2>&1 || code=$?
if grep -q '^WARN  в правилах нет снимков' "$tmp/wc.out" && ! grep -q '^FAIL  в правилах нет снимков' "$tmp/wc.out"; then
  ok "снимок — WARN, а не FAIL"
else ko "снимок — WARN, а не FAIL" "$(cat "$tmp/wc.out")"; fi

mkdir -p "$tmp/ws/memory/issues"
sed -n 6p "$rules" > "$tmp/ws/memory/issues/snap.md"
sed -i '6d' "$rules"
expect "тот же снимок в memory/issues/ — тихо" "PASS  в правилах нет снимков"

printf '%s\n' '```sh' 'sed -n 68p nuxt.config.ts  # nuxt.config.ts:68' '```' >> "$rules"
expect "номер строки в блоке кода — тихо" "PASS  в правилах нет снимков"

cmds="$tmp/ws/memory/commands/frontend.md"
printf '%s\n' '' '## Грабли инструментов' '' '- `vue-tsc ^3.3.11` печатает справку tsc.' >> "$cmds"
expect "версия в разделе «Грабли» — тихо" "PASS  в правилах нет снимков"

printf '%s\n' '' '## Сборка' '' '- Воспроизведено 13.10.2026, npm 10.9.8: `npm error enoent`.' >> "$cmds"
expect "версия в строке с датой — наблюдение, тихо" "PASS  в правилах нет снимков"

printf '%s\n' '- `no-explicit-any` стоит `warn` (сверено по `origin/master` 14.10.2026).' >> "$cmds"
expect "дата сверки — warn и в строке с датой" "memory/commands/frontend.md:$(wc -l < "$cmds" | tr -d ' ') дата сверки"

printf '%s\n' '- Код задачи пока не влит — бери из ветки.' >> "$rules"
expect "статус ветки — warn" ".claude/rules/snap.md:$(wc -l < "$rules" | tr -d ' ') статус ветки"

echo
echo "$total случаев, упало $failed"
[ "$failed" = 0 ]
