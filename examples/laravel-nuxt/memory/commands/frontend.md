---
name: commands-frontend
description: Формы вызова для projects/shop-frontend — dev-сервер, сборка с проверкой типов, линт, генерация клиента API
metadata:
  type: project
---

# Команды — shop-frontend

Записано по `package.json` и `nuxt.config.ts` при `/beerpowers:setup`; при setup формы
не прогонялись.

`npm --prefix` запускает скрипт с рабочим каталогом `projects/shop-frontend`: пути аргументов —
от него.

## Гейты

| Гейт | Форма | Зелёный |
|---|---|---|
| Подготовка `.nuxt` | `npm --prefix projects/shop-frontend run postinstall` | без ошибок `nuxt prepare` |
| Сборка с проверкой типов | `npm --prefix projects/shop-frontend run build` | ноль строк `error TS` в полном логе; код выхода гейтом не является |
| Линт целиком | `npm --prefix projects/shop-frontend run lint` | ноль ошибок ESLint |

Отдельного скрипта `typecheck` нет: типы проверяет `build` (`typescript.typeCheck: true`);
перед ним — `postinstall`: устаревший `.nuxt` даёт ложные `TS2304`. Быстрые гейты — `postinstall`
и `build`: их гоняет и `reviewer` на финальном проходе, если готовых результатов нет.

## Линт

`npm --prefix projects/shop-frontend run lintfix -- <файлы>` — ESLint с автофиксом, только
изменённые файлы, пути от `projects/shop-frontend`. Прямой `npx eslint` из корня workspace
файл может молча не проверить — только через скрипт пакета.

## Dev-сервер

`npm --prefix projects/shop-frontend run dev` — в фоне, PID запомнить при запуске; порт —
по выводу Nuxt (по умолчанию 3000).

## Клиент API

`npm --prefix projects/shop-frontend run generate:api` — orval по `orval.config.ts`: вход
`openapi.json`, вывод `app/api/endpoints.ts` и `app/api/model/`.

