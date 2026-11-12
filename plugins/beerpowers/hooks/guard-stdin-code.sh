#!/bin/sh
# PreToolUse hook (Bash): не даёт запустить интерпретатор с кодом из stdin.
# Флаг barriers.guard-stdin-code в .claude/workspace.json, по умолчанию включён.
#
# Типовой промах: роль правит файл формой `python - <<'EOF' … EOF` — в обход правила
# «файлы пишем Write/Edit». На Windows в Git Bash такой процесс переживает команду и держит
# ядро процессора часами: три python.exe по целому ядру, каждый со своей сессии.
#
# Блокируется: python, py, node, php, ruby, perl, которым код приходит через stdin, —
# аргумент `-`, here-документ или here-строка (`<<`), конвейер (`cat x | python`),
# перенаправление (`python < x.py`).
# Проходит: скрипт по пути (`python fix.py`, `python fix.py <<EOF` — данные скрипту),
# код аргументом (`python -c`, `node -e`, `php -r`), модуль (`python -m json.tool`).

lib="$(dirname -- "$0")/lib/guard.sh"
[ -f "$lib" ] || exit 0
. "$lib"

input=$(cat)
# Ранний отсев по сырому событию — до чтения флага и разбора JSON: барьер срабатывает
# на каждой команде Bash. Нужны имя интерпретатора и источник stdin: `<`, `|` или `-`.
case "$input" in
  *python*|*py\ *|*py.exe*|*node*|*php*|*ruby*|*perl*) ;;
  *) exit 0 ;;
esac
case "$input" in
  *'<'*|*'|'*|*' - '*|*' -"'*|*' -\n'*) ;;
  *) exit 0 ;;
esac

guard_gate guard-stdin-code on

cmd=$(guard_command "$input")
[ -z "$cmd" ] && exit 0

# Тело here-документа — данные: разбирается только строка с его оператором. Оператор
# с разделителем (`<<'EOF'`, `<<-EOF`, `<<< "код"`) заменяется словом `<stdin`: звено,
# где он стоял, получает stdin. Остаток строки (`| python`) разбирается как команда,
# а строки после тела (`|| запасная команда`) — нет.
pre=${cmd%%<<*}
if [ "$pre" != "$cmd" ]; then
  nl='
'
  rest=${cmd#*<<}
  rest=${rest%%"$nl"*}
  rest=${rest%%\\n*}
  rest=$(printf '%s' "$rest" | sed 's/^[<-]*[[:space:]]*\(\\"[^\\]*\\"\|"[^"]*"\|'"'"'[^'"'"']*'"'"'\|[^[:space:];&|]*\)//')
  pre="$pre <stdin $rest"
fi

# Содержимое кавычек — данные, а не команды: `echo "python - <<EOF"` ничего не запускает.
pre=$(printf '%s' "$pre" | sed 's/\\"[^\\]*\\"/_/g; s/"[^"]*"/_/g; s/'"'"'[^'"'"']*'"'"'/_/g')

# Разделители: `&&`, `||`, `;`, `&` и перевод строки (в JSON без jq — `\n`) отделяют
# конвейеры, одиночный `|` — звенья конвейера. Звено после `|` получает stdin от предыдущего.
pre=$(printf '%s' "$pre" | tr '\n' ';' | sed 's/\\n/;/g; s/&&/;/g; s/||/;/g; s/&/;/g')

deny_msg="Интерпретатор с кодом из stdin (python -, here-документ, конвейер в python) на Windows в Git Bash переживает команду и держит ядро процессора часами. Правка файла — инструментом Edit или Write. Разовый скрипт — файл в scratchpad через Write и запуск по пути: python <scratchpad>/fix.py. Короткий код — аргументом: python -c, node -e, php -r."

# check_segment <звено> <stdin перенаправлен: 0|1>
check_segment() {
  segment=$1
  redirected=$2
  case "$segment" in
    *'<'*) redirected=1 ;;
  esac

  # Имя команды — первое слово, не считая присваиваний и обёрток вроде `timeout 60`.
  interp=""
  skip_duration=0
  set -f
  set -- $segment
  set +f
  while [ $# -gt 0 ]; do
    word=$1
    shift
    if [ "$skip_duration" = 1 ]; then
      case "$word" in
        -*) continue ;;
      esac
      skip_duration=0
      continue
    fi
    case "$word" in
      *=*) continue ;;
      env|command|exec|time|nice|winpty|nohup) continue ;;
      timeout) skip_duration=1; continue ;;
    esac
    name=${word##*/}
    name=${name%.exe}
    case "$name" in
      python|python[0-9]*|py|node|php|ruby|perl) interp=$name ;;
    esac
    break
  done
  [ -n "$interp" ] || return 0

  # Опции интерпретатора до первого источника кода. `-` — код из stdin; код аргументом,
  # модуль или путь к скрипту — stdin уже данные, а не код.
  skip_value=0
  for word in "$@"; do
    if [ "$skip_value" = 1 ]; then
      skip_value=0
      continue
    fi
    case "$word" in
      -) guard_deny "$deny_msg" ;;
      -c|-e|-E|-p|-r|-m|-f|--eval|--print|--test|--run) return 0 ;;
      -W|-X|--require|--import|--loader) skip_value=1 ;;
      '<'|'>'|'>>'|[0-9]'>'|[0-9]'>>') skip_value=1 ;;
      '<'*|'>'*|[0-9]'>'*) ;;
      -*) ;;
      *) return 0 ;;
    esac
  done

  # Ни скрипта, ни кода аргументом: интерпретатор читает код из stdin.
  [ "$redirected" = 1 ] && guard_deny "$deny_msg"
  return 0
}

old_ifs=$IFS
IFS=';'
set -f
for pipeline in $pre; do
  IFS='|'
  first=1
  for link in $pipeline; do
    redirected=0
    [ "$first" = 1 ] || redirected=1
    first=0
    IFS=$old_ifs
    set +f
    check_segment "$link" "$redirected"
    set -f
    IFS='|'
  done
  IFS=';'
done
set +f
IFS=$old_ifs

exit 0
