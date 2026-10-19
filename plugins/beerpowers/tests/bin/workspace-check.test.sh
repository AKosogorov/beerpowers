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

echo
echo "$total случаев, упало $failed"
[ "$failed" = 0 ]
