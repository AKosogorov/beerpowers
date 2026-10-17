#!/bin/sh
# PreToolUse hook (Bash): не даёт смешать в одном коммите артефакты задач memory/tasks/**
# с чем-либо ещё. Флаг barriers.guard-commit-split в .claude/workspace.json, по умолчанию включён.
#
# Правило держится не текстом, потому что типовой случай смешения — «APPROVED, закрываю этап»:
# в индекс попадают и review-report.md задачи, и правка памяти роли или charter, и один коммит
# выглядит естественным. Историю по пути memory/tasks однажды вычистят целиком
# (`git filter-repo --path memory/tasks --invert-paths`): отдельные коммиты выпадут чисто,
# смешанные останутся с сообщением про исчезнувшие файлы.
#
# Хук смотрит только на индекс репозитория из -C: в репозиториях кода каталога memory/tasks нет,
# и для них проверка молча проходит.

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

guard_gate guard-commit-split on

cmd=$(guard_command "$input")

[ -z "$cmd" ] && exit 0

naked=$(guard_strip_data "$cmd")
guard_git_sub "$naked" commit || exit 0

# `git commit <пути>` коммитит названные пути поверх индекса — набор файлов тогда не из индекса,
# и хук его не разбирает: ложный deny дороже пропуска.
case "$naked" in
  *commit*" -- "*) exit 0 ;;
esac

repo=$(printf '%s' "$naked" | sed -n 's/.*git[[:space:]]\{1,\}-C[[:space:]]\{1,\}\([^[:space:]]*\).*/\1/p' | head -n 1)
[ -z "$repo" ] && repo="."
# Путь в -C может быть переменной (`git -C $R …`): хук видит текст команды до раскрытия,
# каталога с таким именем нет, и `git diff` молча вернул бы пусто. Тогда проверяем корень проекта.
[ -d "$repo" ] || repo="$GUARD_ROOT"

# Без core.quotePath=false git берёт путь с не-ASCII символами в кавычки, и он не совпал бы
# с маской memory/tasks — смешанный коммит проехал бы.
staged=$(git -c core.quotePath=false -C "$repo" diff --cached --name-only 2>/dev/null)
[ -z "$staged" ] && exit 0

# Сравнение через case, а не grep: путь из workspace.json — литерал, а не регулярка.
tasks=""
other=""
old_ifs=$IFS
IFS='
'
for f in $staged; do
  case "$f" in
    memory/tasks/*) tasks="$tasks$f
" ;;
    *) other="$other$f
" ;;
  esac
done
IFS=$old_ifs

[ -z "$tasks" ] && exit 0
[ -z "$other" ] && exit 0

t_count=$(printf '%s' "$tasks" | wc -l | tr -d ' ')
o_count=$(printf '%s' "$other" | wc -l | tr -d ' ')
o_shown=$(printf '%s' "$other" | head -n 12 | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' '|' | sed 's/|/\\n  /g')

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"В индексе и артефакты задач (%s/**, файлов: %s), и другое (файлов: %s). %s/** коммитится отдельно — историю по этому пути вычистят целиком, смешанный коммит останется выпотрошенным. Разнеси на два коммита: `git reset -q -- %s` и коммит остального, затем `git add %s` и второй коммит. Остальное в индексе:\\n  %s"}}\n' memory/tasks "$t_count" "$o_count" memory/tasks memory/tasks memory/tasks "$o_shown"
exit 0
