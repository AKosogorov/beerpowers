#!/bin/sh
# SessionStart-hook плагина beerpowers: правила ответа человеку, анонс команды и детектор дрейфа
# версий charter <-> плагин. stdout инжектится в контекст главной сессии; субагентам SessionStart
# не приходит. Fail-soft: любая проблема -> обычный анонс или тишина.
# Формат штампа charter — контракт с setup 4.1 и /beerpowers:update: generated-by: beerpowers vX.Y.Z · mode: ...

PLUGIN_ROOT="${1:-$CLAUDE_PLUGIN_ROOT}"

# Правила ответа человеку — rules/<опция>.md, во всех проектах, где включён плагин, с charter
# или без. Опция userConfig приходит переменной CLAUDE_PLUGIN_OPTION_<КЛЮЧ> только после того,
# как пользователь её задал: значение по умолчанию рантайм не экспортирует (замер CLI 2.1.233).
# Поэтому отсутствие переменной значит default из plugin.json — true у всех правил.
first=1
for rule in "$PLUGIN_ROOT"/rules/*.md; do
  [ -f "$rule" ] || continue
  key=$(basename "$rule" .md | tr '[:lower:]' '[:upper:]')
  [ "$(printenv "CLAUDE_PLUGIN_OPTION_$key")" = "false" ] && continue
  if [ "$first" = 1 ]; then
    echo "[beerpowers] Правила ответа человеку. Каждое переключается опцией плагина в /config."
    first=0
  fi
  echo
  cat "$rule"
done
[ "$first" = 0 ] && echo

# cwd hook-процесса не обязан совпадать с корнем проекта — якоримся на $CLAUDE_PROJECT_DIR.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

[ -f .claude/team-charter.md ] || exit 0

PLUGIN_V=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null | head -n 1)
CHARTER_V=$(grep -m 1 -o 'generated-by: beerpowers v[0-9][0-9A-Za-z.-]*' .claude/team-charter.md 2>/dev/null | sed 's/.*beerpowers v//; s/[.-]*$//')
# Charter форка-предка: без этой ветки он попал бы в дрейф «штампа нет» и получил бы
# неверную подсказку про диапазон миграций.
QTIM_V=$(grep -m 1 -o 'generated-by: qtim v[0-9][0-9A-Za-z.-]*' .claude/team-charter.md 2>/dev/null | sed 's/.*qtim v//; s/[.-]*$//')

if [ -z "$CHARTER_V" ] && [ -n "$QTIM_V" ]; then
  echo "[beerpowers] Команда настроена, но проект собран qtim v$QTIM_V, перевод — /beerpowers:update (запись → 2.0.0 в migrations.md). Работать можно и без этого: /beerpowers:team-up | /beerpowers:team-lazy | /beerpowers:team-down (+ /beerpowers:feature, если настроена PM-дорожка)."
elif [ -z "$PLUGIN_V" ] || [ "$CHARTER_V" = "$PLUGIN_V" ]; then
  echo "[beerpowers] Команда агентов настроена (charter найден). Team-lead: до первого вызова Agent прочитай .claude/team-lead.md. /beerpowers:task-start <КОД> — старт или возобновление задачи (перевыгрузит постановку и покажет разницу), /beerpowers:team-lazy — роли по требованию, /beerpowers:team-up — полная команда, /beerpowers:retro — после мержа, /beerpowers:feature — хотелка до плана (если настроена PM-дорожка)."
else
  echo "[beerpowers] Команда настроена, но собрана по версии плагина ${CHARTER_V:-«неизвестной, штампа нет»}, а установлена v$PLUGIN_V — сгенерированные файлы (charter, team-lead.md, агенты, копии .claude/bin и reference) могли разойтись с движком. Запусти /beerpowers:update: миграция подтянет изменения, не трогая проектные блоки и знания в memory/. Работать можно и без этого: /beerpowers:team-up | /beerpowers:team-lazy | /beerpowers:team-down (+ /beerpowers:feature, если настроена PM-дорожка)."
fi

exit 0
