#!/bin/sh
# PreToolUse hook (Bash): не даёт убить процессы, которых роль не запускала.
# Флаг barriers.guard-kill в .claude/workspace.json, по умолчанию включён.
#
# Типовой промах: роль прибирает за собой headless-браузер и вместо своего PID убивает
# все процессы по имени образа — вместе с окнами пользователя.
#
# Маски разрешений тут не помогают по той же причине, что и у guard-push.sh: они матчат
# префикс, а `taskkill //IM chrome.exe //F` идёт другим порядком аргументов. Поэтому
# решение принимается разбором команды.
#
# Проходит: убийство по PID (`taskkill //F //PID 123 //T`, `kill -9 123`).
# Блокируется: убийство по имени образа или шаблону — taskkill //IM, pkill, killall,
# Stop-Process -Name, а также `kill -1` и `kill 0`, которые бьют по группе процессов.

lib="$(dirname -- "$0")/lib/guard.sh"
[ -f "$lib" ] || exit 0
. "$lib"

input=$(cat)
# Ранний отсев по сырому событию — до чтения флага и разбора JSON: барьер срабатывает
# на каждой команде Bash, а каждый запуск sed на Windows стоит десятки миллисекунд.
case "$input" in
  *kill*|*Stop-Process*|*stop-process*) ;;
  *) exit 0 ;;
esac

guard_gate guard-kill on

cmd=$(guard_command "$input")

[ -z "$cmd" ] && exit 0

# Данные — не команды. Тело heredoc и содержимое кавычек могут упоминать любые формы
# убийства процессов: они описывают их, а не выполняют. Кавычки при этом снимаются
# только у аргументов — имя команды в кавычках не разбирается.
cmd=${cmd%%<<*}
raw=$cmd
cmd=$(printf '%s' "$cmd" | sed 's/\\"[^\\]*\\"//g; s/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g')

# Ранний отсев — по строке с кавычками: Stop-Process едет внутри `powershell -c "…"`,
# и на очищенной строке хук вышел бы до разбора.
case "$raw" in
  *taskkill*|*pkill*|*killall*|*Stop-Process*|*stop-process*|*kill*) ;;
  *) exit 0 ;;
esac

deny() {
  guard_deny "$1"
}

check_segment() {
  segment=$1

  # Имя команды — первое слово сегмента, не считая присваиваний переменных окружения
  command_name=""
  for word in $segment; do
    case "$word" in
      *=*) continue ;;
      *) command_name=$word; break ;;
    esac
  done

  case "$command_name" in
    taskkill|taskkill.exe|*/taskkill|*/taskkill.exe)
      has_pid=0
      for word in $segment; do
        case "$word" in
          /PID|//PID|/pid|//pid|/PID:*|//PID:*) has_pid=1 ;;
          /IM|//IM|/im|//im|/IM:*|//IM:*)
            deny "taskkill по имени образа убивает ВСЕ процессы с таким именем, включая окна пользователя: прибирая свой headless-браузер, так сносят весь браузер на машине. Гаси только процесс, который запускал сам: taskkill //F //PID <свой pid> //T. PID своего процесса бери из того, чем его запускал."
            ;;
          /FI|//FI|/fi|//fi)
            deny "taskkill с фильтром //FI бьёт по всем подходящим процессам, а не по твоему. Гаси по PID: taskkill //F //PID <свой pid> //T."
            ;;
        esac
      done
      [ "$has_pid" = "1" ] || deny "У taskkill не указан //PID — цель возьмётся из имени образа или фильтра и заденет чужие процессы. Форма: taskkill //F //PID <свой pid> //T."
      ;;
    pkill|pkill.exe|*/pkill|killall|killall.exe|*/killall)
      deny "$command_name бьёт по имени или шаблону и заденет процессы, которых ты не запускал. Гаси по PID: kill <свой pid> или taskkill //F //PID <свой pid> //T."
      ;;
    kill|kill.exe|*/kill)
      for word in $segment; do
        case "$word" in
          0|-1)
            deny "kill $word посылает сигнал группе процессов, а не одному. Указывай конкретный PID."
            ;;
        esac
      done
      ;;
  esac

  return 0
}

# Stop-Process проверяется по исходной строке, с кавычками: он почти всегда едет
# аргументом `powershell -c "…"`, и снятие кавычек спрятало бы его от разбора.
case "$raw" in
  *Stop-Process*|*stop-process*)
    case "$raw" in
      *-Name*|*-name*|*-ProcessName*|*-processname*)
        deny "Stop-Process -Name останавливает все процессы с таким именем, включая окна пользователя. Указывай -Id <свой pid>."
        ;;
    esac
    ;;
esac

old_ifs=$IFS
IFS='
'
for segment in $(printf '%s' "$cmd" | tr ';&|' '\n\n\n'); do
  IFS=$old_ifs
  check_segment "$segment"
  IFS='
'
done
IFS=$old_ifs

exit 0
