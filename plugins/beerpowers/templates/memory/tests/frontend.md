---
name: tests-frontend
description: Проверка фронтенда {{PROJECT}} — тесты и прогон в браузере, конвенции, регрессионные наборы
metadata:
  type: project
---

# Проверка фронтенда

Тестовый раннер (если есть), конвенции прогона UI в браузере, регрессионные наборы экранов.
Ведёт `tester`. Ловушки самих проб — `probes.md`, неподтверждённое — `unverified.md`.

## Брейкпоинты

Ширины прогона — ключ `viewports` в `.claude/workspace.json`, список печатает
`node .claude/bin/cdp-screenshot.mjs --viewports`. Здесь — откуда он взят, чтобы при правке вёрстки
сверить список с кодом:

{{BREAKPOINTS}}
