#!/bin/sh
# PreToolUse hook (Bash): не даёт закоммитить новые комментарии, не показав их глазами.
# Флаг barriers.guard-comments в .claude/workspace.json, по умолчанию включён.
#
# Правило требует перед сдачей перечитать добавленные строки комментариев в диффе и удалить
# пересказ кода. Правило текстом не работает: комментарий в момент написания ощущается как
# добросовестность, и перечитывание пропускается — мусор ловит ревьюер или пользователь,
# а не автор.
#
# Машинно отличить нужный комментарий от пересказа нельзя, поэтому хук не оценивает
# содержание. Он печатает добавленные комментарии и блокирует коммит ровно один раз:
# повторный коммит того же индекса проходит. Цена — один лишний шаг, смысл — комментарии
# гарантированно попадают на глаза до того, как уедут в историю.
#
# Каталоги comments.excludeDirs своего репозитория исключены: генерируемый код приносит
# комментарии десятками при каждой регенерации, руками он не правится, и показ его строк
# только топит настоящие.

lib="$(dirname -- "$0")/lib/guard.sh"
[ -f "$lib" ] || exit 0
. "$lib"

input=$(cat)
# Ранний отсев по сырому событию — до чтения флага и разбора JSON: барьер срабатывает
# на каждой команде Bash, а каждый запуск sed на Windows стоит десятки миллисекунд.
case "$input" in
  *commit*) ;;
  *) exit 0 ;;
esac

guard_gate guard-comments on

STATE_DIR="$GUARD_ROOT/.claude/.cache"
STATE_FILE="$STATE_DIR/comment-guard"

cmd=$(guard_command "$input")

[ -z "$cmd" ] && exit 0

# Данные — не команды: тело сообщения коммита может упоминать любые формы git.
naked=$(guard_strip_data "$cmd")
guard_git_sub "$naked" commit || exit 0

# Каталог репозитория: из флага -C, иначе текущий. Путь в -C может быть переменной
# (`git -C $R …`): хук видит текст до раскрытия, каталога с таким именем нет, и git молча
# вернул бы пусто — тогда проверяется корень проекта.
repo=$(printf '%s' "$naked" | sed -n 's/.*git[[:space:]]\{1,\}-C[[:space:]]\{1,\}\([^[:space:]]*\).*/\1/p' | head -n 1)
[ -z "$repo" ] && repo="."
[ -d "$repo" ] || repo="$GUARD_ROOT"

# `commit -a` / `--all` забирает и неиндексированные правки отслеживаемых файлов: их комментарии
# видны только в диффе от HEAD.
range=--cached
if printf '%s' "$naked" | grep -Eq 'commit([[:space:]].*)?[[:space:]](-[A-Za-z]*a[A-Za-z]*|--all)([[:space:]]|$)'; then
  range=HEAD
fi

# Исключения записаны путём от корня workspace — projects/<репо>/<путь> — и действуют только
# в своём репозитории: один и тот же каталог генерируемый в одном и рукописный в другом.
# Репозиторий узнаётся по имени каталога: рабочее дерево задачи названо так же, как репозиторий
# (worktrees/<КОД>/<репо>), поэтому запись покрывает и его.
repo_name=$(basename -- "$(cd -- "$repo" 2>/dev/null && pwd)")
excluded=""
for dir in $(guard_ws_list excludeDirs); do
  dir=${dir%/}
  case "$dir" in
    "projects/$repo_name/"?*) excluded="$excluded ${dir#"projects/$repo_name/"}" ;;
  esac
done

# Добавленные строки по маске расширений ($@), без каталогов-исключений.
added_lines() {
  for dir in $excluded; do
    set -- "$@" ":(exclude)$dir/*"
  done
  git -C "$repo" diff $range -U0 -- "$@" 2>/dev/null | grep '^+' | grep -v '^+++'
}

# Комментарий в начале строки и в конце строки после кода. Перед хвостовым `//` и `#` нужен
# пробел: так `https://` и `${#var}` комментарием не считаются.
slash=$(added_lines '*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs' '*.cjs' '*.vue' '*.svelte' '*.php' \
  '*.css' '*.scss' '*.less' '*.go' '*.java' '*.kt' '*.kts' '*.swift' '*.rs' \
  '*.c' '*.h' '*.cc' '*.cpp' '*.hpp' '*.cs' '*.scala' '*.dart' '*.html' \
  | grep -E '^\+[[:space:]]*(//|/\*|\*[^/]|<!--|\{\{--)|^\+.*[^[:space:]][[:space:]]+(//|/\*)|<!--|\{\{--')
# `#!` — shebang, `#[` — атрибут PHP: не комментарии.
hash=$(added_lines '*.py' '*.sh' '*.bash' '*.rb' '*.pl' '*.yml' '*.yaml' '*.toml' '*.php' \
  '*.ex' '*.exs' '*Dockerfile' \
  | grep -E '^\+[[:space:]]*#([^![]|$)|^\+.*[^[:space:]][[:space:]]+#[[:space:]]')

added=$(printf '%s\n%s\n' "$slash" "$hash" | grep -v '^$')

[ -z "$added" ] && exit 0

# Тот же набор комментариев уже показывали — пропускаем, иначе коммит не сделать никогда.
fingerprint=$(printf '%s' "$added" | git hash-object --stdin 2>/dev/null)
if [ -n "$fingerprint" ] && [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "$fingerprint" ]; then
  exit 0
fi

mkdir -p "$STATE_DIR" 2>/dev/null
[ -n "$fingerprint" ] && printf '%s' "$fingerprint" > "$STATE_FILE"

count=$(printf '%s\n' "$added" | wc -l | tr -d ' ')
shown=$(printf '%s\n' "$added" | head -n 30 | sed 's/^+//' | sed 's/^[[:space:]]*//' | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' '|' | sed 's/|/\\n  /g')

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Новых строк комментариев в индексе: %s. Перечитай их и удали те, что пересказывают строку под собой или защищают ожидаемое поведение; оставь только неочевидное «почему» — скрытое ограничение, обходной путь, неожиданное поведение стороннего кода.\\n\\n  %s\\nПовтори ту же команду коммита, когда решишь по каждому: тот же набор строк второй раз не блокируется."}}\n' "$count" "$shown"
exit 0
