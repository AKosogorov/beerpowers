#!/bin/sh
# yandex-tracker-write без сети: проверка черновика против шаблона и команды записи против
# заглушки API (tracker-api-stub.mjs), которая держит поведение живого Трекера там, где на нём
# держится скрипт: одна связь на пару задач, версия растёт с вложением, 409 на старую версию.
# Последний случай сверяет секции шаблона скрипта с таблицами скила beerpowers:tracker-task.
#
# Запуск: sh plugins/beerpowers/tests/bin/yandex-tracker-write.test.sh

here=$(cd -- "$(dirname -- "$0")" && pwd)
src="$here/../../templates/bin/yandex-tracker-write.mjs"
skill="$here/../../skills/tracker-task/SKILL.md"

tmp=$(mktemp -d 2>/dev/null) || tmp="${TMPDIR:-/tmp}/bp-ytw-$$"
mkdir -p "$tmp/ws/.claude/bin" "$tmp/home/.claude" "$tmp/d" || exit 2
sed 's/{{BEERPOWERS_VERSION}}/0.0.0/' "$src" > "$tmp/ws/.claude/bin/yandex-tracker-write.mjs"
w="$tmp/ws/.claude/bin/yandex-tracker-write.mjs"

node "$here/tracker-api-stub.mjs" "$tmp/port" "$tmp/log" &
stub=$!
trap 'kill $stub 2>/dev/null; rm -rf "$tmp"' EXIT
i=0
while [ ! -s "$tmp/port" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
[ -s "$tmp/port" ] || { echo "заглушка API не поднялась"; exit 2; }
port=$(cat "$tmp/port")

total=0
failed=0

# t <имя> <код> <ожидание>… -- <аргументы скрипта>: ожидание «текст» — есть в выводе,
# «!текст» — нет в нём, «log:текст» — есть в журнале запросов, «nolog:текст» — нет в нём.
# Журнал чистится перед каждым случаем. Переменная sid — id сессии Claude Code для случая:
# пустая — модель сессии скрипту не узнать.
t() {
  name=$1
  want_code=$2
  shift 2
  wants=""
  while [ "$1" != "--" ]; do wants="$wants
$1"; shift; done
  shift
  total=$((total + 1))
  : > "$tmp/log"
  out=$(env -u YANDEX_TRACKER_ORG_TYPE -u CLAUDE_CODE_SESSION_ID YANDEX_TRACKER_TOKEN=t YANDEX_TRACKER_ORG_ID=1 \
    YANDEX_TRACKER_API_HOST="http://127.0.0.1:$port" CLAUDE_CONFIG_DIR="$tmp/home/.claude" \
    ${sid:+"CLAUDE_CODE_SESSION_ID=$sid"} node "$w" "$@" 2>&1)
  code=$?
  ok=1
  why=""
  [ "$code" = "$want_code" ] || { ok=0; why="код $code, ждали $want_code"; }
  printf '%s\n' "$wants" | while IFS= read -r want; do
    [ -n "$want" ] || continue
    case "$want" in
      log:*) grep -qF -- "${want#log:}" "$tmp/log" || echo "в запросах нет «${want#log:}»" ;;
      nolog:*) grep -qF -- "${want#nolog:}" "$tmp/log" && echo "в запросах есть «${want#nolog:}»" ;;
      !*) printf '%s' "$out" | grep -qF -- "${want#!}" && echo "в выводе есть «${want#!}»" ;;
      *) printf '%s' "$out" | grep -qF -- "$want" || echo "в выводе нет «$want»" ;;
    esac
  done > "$tmp/why"
  [ -s "$tmp/why" ] && { ok=0; why="$why $(tr '\n' ';' < "$tmp/why")"; }
  if [ "$ok" = 1 ]; then
    echo "pass  $name"
  else
    failed=$((failed + 1))
    echo "FAIL  $name — $why"
    printf '%s\n' "$out" | head -n 8 | sed 's/^/      /'
  fi
}

sign='© Клод Клодыч Опусович'
sid=''
# Транскрипт сессии на Sonnet: служебная запись без модели последней, ответ модели — перед ней.
mkdir -p "$tmp/home/.claude/projects/ws"
printf '%s\n' '{"type":"assistant","message":{"model":"claude-sonnet-5-5"}}' \
  '{"type":"assistant","message":{"model":"<synthetic>"}}' > "$tmp/home/.claude/projects/ws/s-sonnet.jsonl"

# draft <файл> <название> <теги> <связи> <тело>: черновик задачи в $tmp/d.
draft() {
  cat > "$tmp/d/$1" <<EOF
# $2

| Поле | Значение |
|---|---|
| Очередь | QQ |
| Тип | Задача |
| Доска | 7 |
| Теги | $3 |
| Исполнитель | — |
| QA | — |
| Ревьюер | — |
| Связи | $4 |

---

$5
EOF
}

body_ok="**Зависит от:**
- QQ-90 — первая сборка фида.

## Цель

Посетитель видит фид по постоянному адресу.

## Что делаем

- Адрес отдаёт файл, детали — в [tech.md](tech.md), правила — [по ссылке](https://example.test/rules).

![экран](shot.png)

## Критерии приёмки

- Посетитель открывает адрес — видит файл.

$sign"
printf 'тех\n' > "$tmp/d/tech.md"
printf 'png\n' > "$tmp/d/shot.png"

draft ok.md 'Фид по постоянному адресу (front)' Frontend 'зависит от QQ-90' "$body_ok"
t "check: чистый черновик проходит" 0 "сходится с шаблоном" -- check "$tmp/d/ok.md"

node "$w" template task > "$tmp/d/tpl.md" 2>/dev/null
t "check: пустой шаблон не проходит" 1 "незаполненное место шаблона" -- check "$tmp/d/tpl.md"

draft nosuffix.md 'Фид по постоянному адресу' Frontend 'зависит от QQ-90' "$body_ok"
t "check: тег Frontend без (front) в названии" 1 "«(front)»" -- check "$tmp/d/nosuffix.md"

draft both.md 'Фид (front)' 'Frontend, Backend' 'зависит от QQ-90' "$body_ok"
t "check: оба тега — две задачи" 1 "две задачи" -- check "$tmp/d/both.md"

draft nolink.md 'Фид по постоянному адресу (front)' Frontend '—' "$body_ok"
t "check: зависимость из шапки без связи" 1 "нужно «зависит от QQ-90»" -- check "$tmp/d/nolink.md"

draft wrongkind.md 'Фид по постоянному адресу (front)' Frontend 'связана с QQ-90' "$body_ok"
t "check: зависимость связана не тем видом" 1 "нужно «зависит от QQ-90»" -- check "$tmp/d/wrongkind.md"

draft nosign.md 'Фид (front)' Frontend 'зависит от QQ-90' "$(printf '%s' "$body_ok" | sed '$d')"
t "check: без подписи" 1 "подпись" -- check "$tmp/d/nosign.md"

draft order.md 'Фид (front)' Frontend '—' "## Что делаем

- Пункт.

## Цель

Цель.

## Критерии приёмки

- Критерий.

$sign"
t "check: секция не на своём месте" 1 "не на своём месте" -- check "$tmp/d/order.md"

draft extra.md 'Фид (front)' Frontend '—' "## Цель

Цель.

## Зачем

Потому что.

## Что делаем

- Пункт.

## Критерии приёмки

- Критерий.

$sign"
t "check: секции нет в шаблоне" 1 "секции «Зачем» в шаблоне задачи нет" -- check "$tmp/d/extra.md"

draft money.md 'Фид (front)' Frontend '—' "## Цель

Цель за 4 500 ₽.

## Что делаем

- Пункт.

## Критерии приёмки

- Критерий.

$sign"
t "check: деньги в тексте" 1 "деньги в тексте" -- check "$tmp/d/money.md"

draft prose.md 'Фид (front)' Frontend '—' "Вступление без шапки.

## Цель

Цель.

## Что делаем

- Пункт.

## Критерии приёмки

- Критерий.

$sign"
t "check: текст до первой секции — не шапка" 1 "только шапка" -- check "$tmp/d/prose.md"

cat > "$tmp/d/bug.md" <<EOF
# Каталог: фильтр откатывает выбор (front)

| Поле | Значение |
|---|---|
| Очередь | QQ |
| Тип | Ошибка |
| Доска | 7 |
| Теги | Frontend |
| Связи | — |

---

## Где

- https://example.test/catalog, телефон 390×844.

## Шаги воспроизведения

1. Открыть каталог.

## Фактический результат

- Выбор сброшен.

## Ожидаемый результат

- Выбор сохранён.

$sign
EOF
t "check: баг без обязательных секций" 1 "нет обязательной секции «Доказательства»" "нет обязательной секции «Влияние»" -- check "$tmp/d/bug.md"

t "check: create без чистого check ничего не шлёт" 1 "ничего не отправлено" "nolog:POST /issues" -- create "$tmp/d/nosuffix.md"

t "create: вложения загружены, адреса подставлены, автосвязь заменена видом из черновика" 0 "создана: QQ-1" "(была «связана»)" \
  "log:POST /attachments" 'log:"attachmentIds":["1","2"]' "log:/ajax/v2/attachments/2?inline=true){type=\\\"text/markdown\\\"}" \
  "log:![экран](/ajax/v2/attachments/1?inline=true)" 'log:"boards":[{"id":7}]' 'log:{orange}(*© Клод Клодыч Опусович*)' 'log:[по ссылке](https://example.test/rules)' 'log:"tags":["Frontend"]' \
  'log:POST /issues/QQ-1/links {"relationship":"depends on","issue":"QQ-90"}' -- create "$tmp/d/ok.md"

t "link: та же связь — без записи" 0 "связь уже есть" "nolog:POST /issues/QQ-1/links" -- link QQ-1 зависит-от QQ-90
t "link: другой вид на ту же пару — отказ без --replace" 1 "уже есть связь «зависит-от»" "nolog:POST /issues/QQ-1/links" -- link QQ-1 связана QQ-90
t "link: --replace меняет вид" 0 "была «зависит-от»" 'log:{"relationship":"relates","issue":"QQ-90"}' -- link QQ-1 связана QQ-90 --replace
t "links: вид виден с обеих сторон" 0 "связана QQ-1" -- links QQ-90
t "unlink: связь удалена" 0 "связь удалена" "log:DELETE /issues/QQ-1/links/" -- unlink QQ-1 QQ-90
t "unlink: связи нет — отказ" 1 "связи QQ-1 — QQ-90 нет" -- unlink QQ-1 QQ-90

t "edit: версия перечитана после загрузок, 409 нет" 0 "изменена: QQ-1" "log:POST /issues/QQ-1/attachments" "log:PATCH /issues/QQ-1?version=3" -- edit QQ-1 "$tmp/d/ok.md"

draft tracker.md 'Фид по постоянному адресу (front)' Frontend '—' "## Цель

Цель, детали — в :file[tech.md](/ajax/v2/attachments/3?inline=true){type=\"text/markdown\"}.

## Что делаем

- Пункт.

## Критерии приёмки

- Критерий.

{orange}(*$sign*)"
t "edit: разметка Трекера из задачи проходит как есть" 0 "изменена: QQ-1" "nolog:POST /issues/QQ-1/attachments" \
  'log::file[tech.md](/ajax/v2/attachments/3?inline=true)' '!(*{orange}' -- edit QQ-1 "$tmp/d/tracker.md"

draft ok2.md 'Фид по постоянному адресу (front)' Frontend 'зависит от QQ-90' "$body_ok"
t "edit: черновик снова с локальными файлами" 0 "изменена: QQ-1" -- edit QQ-1 "$tmp/d/ok2.md"

t "detach: вложение из описания — отказ" 1 "упомянуто в описании" "nolog:DELETE" -- detach QQ-1 5
t "detach: вложение без ссылок удаляется" 0 "удалено" "log:DELETE /issues/QQ-1/attachments/1" -- detach QQ-1 1

printf 'Готово.\n' > "$tmp/d/c1.md"
t "comment: без подписи не уходит" 1 "подпись" "nolog:POST /issues/QQ-1/comments" -- comment QQ-1 "$tmp/d/c1.md"
printf 'Чеклист — [qa.html](qa.html)\n\n%s\n' "$sign" > "$tmp/d/c2.md"
printf '<html></html>\n' > "$tmp/d/qa.html"
t "comment: файл временной загрузкой" 0 "комментарий" "log:POST /attachments" 'log:{type=\"text/html\"}' -- comment QQ-1 "$tmp/d/c2.md"

printf 'Сделано.\n\n%s\n' "$sign" > "$tmp/d/c3.md"
t "comment: без сессии подпись сверяется только по форме" 0 "комментарий" -- comment QQ-1 "$tmp/d/c3.md"
printf 'Сделано.\n\n© Клод Клодыч Сонетыч\n' > "$tmp/d/c4.md"
t "comment: строка с © не по форме подписи — отказ" 1 "не подпись" "nolog:POST /issues/QQ-1/comments" -- comment QQ-1 "$tmp/d/c4.md"

sid=s-sonnet
t "template: подпись по модели сессии" 0 "© Клод Клодыч Сонетович" "!<Опусович" -- template task
t "check: подпись не по модели сессии — отказ" 1 "не по модели сессии (sonnet)" -- check "$tmp/d/ok.md"
t "comment: подпись не по модели сессии не уходит" 1 "не по модели сессии" "nolog:POST /issues/QQ-1/comments" -- comment QQ-1 "$tmp/d/c3.md"
t "comment: подпись дописана по модели сессии" 0 "комментарий 3" 'log:Готово.\n\n{orange}(*© Клод Клодыч Сонетович*)' -- comment QQ-1 "$tmp/d/c1.md"
printf 'Готово, чуть иначе.\n\n© Клод Клодыч Сонетович\n' > "$tmp/d/c5.md"
t "edit-comment: свой комментарий изменён" 0 "комментарий 3 изменён" 'log:PATCH /issues/QQ-1/comments/3 {"text":"Готово, чуть иначе.\n\n{orange}(*© Клод Клодыч Сонетович*)"' -- edit-comment QQ-1 3 "$tmp/d/c5.md"
t "edit-comment: подпись не по модели — отказ до запроса" 1 "не изменён" "nolog:GET /issues/QQ-1/comments/3" -- edit-comment QQ-1 3 "$tmp/d/c3.md"
printf 'чужой отзыв\n' > "$tmp/d/c6.md"
t "comment: от другого автора (заглушка)" 0 "комментарий 4" -- comment QQ-1 "$tmp/d/c6.md"
t "comments: список с авторами и своими" 0 "3  Заглушка (свой)  Готово, чуть иначе." "4  Другой  чужой отзыв" -- comments QQ-1
t "comments: один комментарий целиком" 0 "автор Заглушка" "Сонетович" -- comments QQ-1 3
t "edit-comment: чужой — отказ" 1 "чужой комментарий" "nolog:PATCH" -- edit-comment QQ-1 4 "$tmp/d/c5.md"
t "delete-comment: чужой — отказ" 1 "чужой комментарий" "nolog:DELETE" -- delete-comment QQ-1 4
t "delete-comment: свой удалён" 0 "комментарий 3 удалён" "log:DELETE /issues/QQ-1/comments/3" -- delete-comment QQ-1 3
t "delete-comment: нет комментария — ответ Трекера" 1 "404" -- delete-comment QQ-1 3
sid=''

t "move: поле перехода не задано — ответ Трекера" 1 "Резолюция" -- move QQ-1 close
t "move: с резолюцией" 0 "Закрыт" 'log:{"resolution":"fixed"}' -- move QQ-1 close --resolution fixed
t "transitions: резолюции типа" 0 "fixed, wontFix" -- transitions QQ-1

# Секции шаблона скрипта — те же и в том же порядке, что в таблицах скила.
total=$((total + 1))
for kind in task bug; do
  case $kind in task) head='## Секции задачи' ;; bug) head='## Секции бага' ;; esac
  node "$w" template $kind | sed -n 's/^## //p' > "$tmp/script-$kind"
  awk -v h="$head" '$0 == h { on = 1; next } on && /^## / { exit } on' "$skill" \
    | sed -n 's/^| `## \([^`]*\)`.*/\1/p' > "$tmp/skill-$kind"
done
if cmp -s "$tmp/script-task" "$tmp/skill-task" && cmp -s "$tmp/script-bug" "$tmp/skill-bug" && [ -s "$tmp/skill-task" ]; then
  echo "pass  секции шаблона = таблицы скила tracker-task"
else
  failed=$((failed + 1))
  echo "FAIL  секции шаблона расходятся со скилом tracker-task"
  diff "$tmp/script-task" "$tmp/skill-task" | sed 's/^/      /'
  diff "$tmp/script-bug" "$tmp/skill-bug" | sed 's/^/      /'
fi

echo
echo "$total случаев, упало $failed"
[ "$failed" = 0 ]
