#!/bin/sh
# layout-check.mjs на одноразовой фикстуре: «сервер» — голый репозиторий фронта, клон
# в projects/front на ветке задачи. Каждый случай — правка поверх базы, вердикт и код выхода.
#
# Запуск: sh plugins/beerpowers/tests/bin/layout-check.test.sh

here=$(cd -- "$(dirname -- "$0")" && pwd)
bin=$(cd -- "$here/../../templates/bin" && pwd)

tmp=$(mktemp -d 2>/dev/null) || tmp="${TMPDIR:-/tmp}/bp-layout-$$"
mkdir -p "$tmp" || exit 2
trap 'rm -rf "$tmp"' EXIT

ws="$tmp/ws"
repo="$ws/projects/front"
mkdir -p "$tmp/seed/app/components" "$tmp/seed/app/stores" "$tmp/seed/app/assets" "$tmp/seed/locales" \
  "$ws/.claude/bin/lib" "$ws/projects"
cp "$bin/layout-check.mjs" "$ws/.claude/bin/"
cp "$bin/lib/workspace.mjs" "$bin/lib/git.mjs" "$ws/.claude/bin/lib/"
printf '%s\n' '{ "beerpowers": "2.0.0", "ui": true }' > "$ws/.claude/workspace.json"

g() { git -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false "$@"; }

seed="$tmp/seed"
printf '%s\n' "export const useForm = () => ({ phone: '' })" > "$seed/app/stores/form.ts"
printf '%s\n' \
  '<template>' \
  '  <form class="flex gap-2">' \
  '    <UInput v-model="phone" placeholder="Телефон" />' \
  '    <UButton class="px-4">Отправить</UButton>' \
  '  </form>' \
  '</template>' \
  '' \
  '<script setup lang="ts">' \
  "const phone = ref('')" \
  '</script>' \
  '' \
  '<style scoped>' \
  '.hint { color: red; }' \
  '</style>' > "$seed/app/components/Form.vue"
printf '%s\n' 'body { margin: 0; }' > "$seed/app/assets/main.css"
printf '%s\n' '{' '  "send": "Отправить"' '}' > "$seed/locales/ru.json"
git init -q "$seed"
g -C "$seed" add -A
g -C "$seed" commit -q -m init
git init -q --bare "$tmp/srv.git"
g -C "$seed" push -q "$tmp/srv.git" HEAD:refs/heads/main
git -C "$tmp/srv.git" symbolic-ref HEAD refs/heads/main
git clone -q "$tmp/srv.git" "$repo"
g -C "$repo" checkout -q -b PROJ-1

form="$repo/app/components/Form.vue"
total=0
failed=0

reset() {
  g -C "$repo" checkout -q -- .
  g -C "$repo" clean -q -fd
}

# edit <файл> <sed-выражение>: правка файла рабочего дерева.
edit() {
  sed "$2" "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# case_ <имя> <код выхода> <текст в выводе>: прогон по текущему состоянию дерева, затем сброс.
case_() {
  name=$1 want_code=$2 want=$3
  total=$((total + 1))
  out=$(node "$ws/.claude/bin/layout-check.mjs" PROJ-1 front 2>&1)
  code=$?
  if [ "$code" = "$want_code" ] && printf '%s' "$out" | grep -qF -- "$want"; then
    echo "pass  $name"
  else
    failed=$((failed + 1))
    echo "FAIL  $name — код $code (ждали $want_code), нет «$want»?"
    printf '%s\n' "$out" | sed 's/^/      /'
  fi
  reset
}

# Правка как в прецеденте: начальное значение поля и удалённый placeholder.
edit "$repo/app/stores/form.ts" "s/phone: ''/phone: '+7 '/"
edit "$form" 's/ placeholder="Телефон"//'
case_ 'значение по умолчанию и удалённый placeholder — pass' 0 'ИТОГ  pass'

edit "$form" 's/px-4/px-6/'
case_ 'класс Tailwind — fail' 1 'атрибут class у <UButton>'

edit "$form" 's|    <UButton|    <div><UButton|; s|</UButton>|</UButton></div>|'
case_ 'обёртка в шаблоне — fail' 1 'изменились теги или компоненты шаблона'

edit "$form" 's/>Отправить</>Отправить заявку</'
case_ 'длина текста кнопки — fail' 1 'изменилась длина текста'

edit "$form" 's/>Отправить</>Направить</'
case_ 'текст той же длины — pass' 0 'ИТОГ  pass'

edit "$form" "s/const phone = ref('')/const { md } = useBreakpoints(breakpointsTailwind)/"
case_ 'useBreakpoints в script — fail' 1 'ширину'

edit "$form" 's/color: red/color: blue/'
case_ 'блок style — fail' 1 'изменился блок <style>'

edit "$repo/app/assets/main.css" 's/margin: 0/margin: 4px/'
case_ 'файл стилей — fail' 1 'файл стилей'

printf '%s\n' '<template><span /></template>' > "$repo/app/components/New.vue"
case_ 'новый компонент — fail' 1 'добавлен компонент'

edit "$repo/locales/ru.json" 's/"Отправить"/"Отправить заявку"/'
case_ 'длина текста перевода — fail' 1 'ключа send'

edit "$form" 's/v-model="phone"/v-model="phone" maxlength="18" @blur="touch"/'
case_ 'атрибуты без влияния на раскладку — pass' 0 'ИТОГ  pass'

case_ 'нет изменений — pass' 0 'изменений нет'

total=$((total + 1))
out=$(node "$ws/.claude/bin/layout-check.mjs" PROJ-1 nope 2>&1)
if [ $? = 2 ] && printf '%s' "$out" | grep -qF 'ИТОГ  ошибка'; then
  echo "pass  неизвестный репозиторий — код 2"
else
  failed=$((failed + 1))
  echo "FAIL  неизвестный репозиторий — код 2"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

echo
echo "$total случаев, упало $failed"
[ "$failed" = 0 ]
