# Общая часть барьеров плагина: гейт по charter и флагу, чтение .claude/workspace.json
# и поля из JSON события. Подключается точкой из hooks/*.sh; сам по себе не запускается.
#
# Параметры читаются sed'ом, без node и jq: хук обязан работать на любой машине команды,
# а node и jq есть не везде. Контракт формата — reference/workspace.md, «Чтение из хуков».

GUARD_ROOT=${CLAUDE_PROJECT_DIR:-.}
GUARD_WS="$GUARD_ROOT/.claude/workspace.json"

# Файл сплющивается в одну строку: значение читается одинаково, записан ли массив
# в строку или разнесён по строкам, и CRLF с Windows-машины не попадает в значения.
guard_ws_flat() {
  [ -f "$GUARD_WS" ] || return 0
  tr -d '\r\n' < "$GUARD_WS"
}

# Элементы массива строк по одному на строку вывода. Элемент не может содержать
# кавычку, запятую и `]` — разбор идёт по ним, а не JSON-парсером.
guard_ws_list() {
  guard_ws_flat \
    | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p" \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//' \
    | grep -v '^[[:space:]]*$'
}

# Флаг барьера: true/false из workspace.json, иначе дефолт (on|off).
guard_flag() {
  guard_v=$(guard_ws_flat | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\([a-z]*\).*/\1/p")
  case "$guard_v" in
    true) return 0 ;;
    false) return 1 ;;
  esac
  [ "$2" = "on" ]
}

# Барьеры действуют только в проектах с командой; выключенный флагом барьер молчит.
# Без имени барьера — только проверка charter (guard-agent-memory не выключается).
guard_gate() {
  [ -f "$GUARD_ROOT/.claude/team-charter.md" ] || exit 0
  [ -z "$1" ] && return 0
  guard_flag "$1" "$2" || exit 0
}

# jq, если есть: он разбирает JSON точно. Иначе sed с захватом до первой неэкранированной
# кавычки — жадный `\(.*\)` уезжал за границы поля и подхватывал соседние, в том числе
# `description`, из-за чего решение принималось по тексту, который не исполняется.
guard_command() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r '.tool_input.command // empty' 2>/dev/null
  else
    printf '%s' "$1" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(\([^"\\]\|\\.\)*\)".*/\1/p' | head -n 1
  fi
}

guard_file_path() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r '.tool_input.file_path // empty' 2>/dev/null
  else
    printf '%s' "$1" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
  fi
}

# Строковое поле события: $2 — путь jq, $3 — имя ключа для разбора sed'ом без jq.
guard_json() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r "$2 // empty" 2>/dev/null
  else
    printf '%s' "$1" | sed -n 's/.*"'"$3"'"[[:space:]]*:[[:space:]]*"\(\([^"\\]\|\\.\)*\)".*/\1/p' | head -n 1
  fi
}

# Команда без данных: тело heredoc отрезается, строка в кавычках с пробелом (сообщение коммита,
# тело MR) заменяется на `_` — она описывает формы git, а не выполняет их. Строка без пробела
# раскрывается в слово: это путь `-C "D:/x"`, и пустое место на его месте сдвинуло бы разбор —
# подкомандой стало бы слово после неё. Формы — для экранированных \" (разбор без jq)
# и для обычных кавычек.
guard_strip_data() {
  printf '%s' "${1%%<<*}" | sed 's/\\"\([^\\ ]*\)\\"/\1/g; s/\\"[^\\]*\\"/_/g; s/"\([^" ]*\)"/\1/g; s/"[^"]*"/_/g; s/'"'"'\([^'"'"' ]*\)'"'"'/\1/g; s/'"'"'[^'"'"']*'"'"'/_/g'
}

# Есть ли в команде $1 (уже без данных) вызов `git … $2`. Подкоманда — первое слово после git
# и его опций; подстрока не годится: `git rm guard-commit-split.sh` содержит «commit».
# Сегменты составной команды проверяются каждый.
guard_git_sub() {
  _gs_ifs=$IFS
  IFS='
'
  for _gs_seg in $(printf '%s' "$1" | tr ';&|' '\n\n\n'); do
    IFS=$_gs_ifs
    _gs_git=0
    _gs_skip=0
    for _gs_w in $_gs_seg; do
      if [ "$_gs_skip" = 1 ]; then
        _gs_skip=0
        continue
      fi
      if [ "$_gs_git" = 0 ]; then
        case "$_gs_w" in
          git|git.exe|*/git|*/git.exe) _gs_git=1 ;;
        esac
        continue
      fi
      case "$_gs_w" in
        -C|-c|--git-dir|--work-tree|--namespace|--exec-path) _gs_skip=1 ;;
        -*) ;;
        *)
          if [ "$_gs_w" = "$2" ]; then
            IFS=$_gs_ifs
            return 0
          fi
          break
          ;;
      esac
    done
    IFS='
'
  done
  IFS=$_gs_ifs
  return 1
}

guard_deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}
