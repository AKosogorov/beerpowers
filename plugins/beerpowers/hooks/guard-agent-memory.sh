#!/bin/sh
# PreToolUse hook (Edit|Write): в память роли (.claude/agent-memory/<роль>/) пишутся только
# feedback_*.md и индекс MEMORY.md. Флага нет — действует в каждом проекте с charter.
#
# Техники проб, факты о проекте и формы команд, записанные ролью «себе», растут вне памяти
# проекта и расходятся с ней: за несколько недель там набираются десятки reference_*
# и project_*, дублирующих или противоречащих memory/. Правило текстом не держится: роль
# в конце захода пишет туда, что помнит, и перечитывать таблицу «Куда класть находку» не идёт.
# Хук возвращает запись в memory/ репозитория указателем на таблицу; feedback_* остаётся —
# это обратная связь человека роли, у неё нет другого адресата.

lib="$(dirname -- "$0")/lib/guard.sh"
[ -f "$lib" ] || exit 0
. "$lib"

guard_gate

input=$(cat)
file=$(guard_file_path "$input")

[ -z "$file" ] && exit 0

# На Windows путь приходит с обратными слэшами, а без jq — ещё и JSON-экранированными
# (`\\`): после замены остаются двойные `//`, и маска ниже не совпала бы. Отсюда сжатие.
norm=$(printf '%s' "$file" | tr '\\' '/' | tr -s '/')

case "$norm" in
  */.claude/agent-memory/*|.claude/agent-memory/*) ;;
  */.claude/agent-memory-local/*|.claude/agent-memory-local/*) ;;
  *) exit 0 ;;
esac

base=${norm##*/}

case "$base" in
  MEMORY.md|feedback_*.md) exit 0 ;;
esac

guard_deny "В память роли пишутся только feedback_*.md и MEMORY.md. Файл $base — знание о проекте или инструменте: его место в memory/ репозитория по таблице «Куда класть находку» в memory/MEMORY.md. Запиши туда и дай ссылку в отчёте team-lead-у."
