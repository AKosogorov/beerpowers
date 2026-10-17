---
name: project-map
description: Карта shop — репозитории, слои, раскладка, точки входа
metadata:
  type: project
---

# Карта проекта

Заполнено фактами Discovery при `/beerpowers:setup`; глубокое наполнение — `/beerpowers:onboard`.

## Workspace

Раскладка `multi` (`.claude/workspace.json`): корень — репозиторий конфигурации команды
и памяти, ветка `master`; репозитории кода — в `projects/`, под gitignore корня.

| Репозиторий | Путь | Стек | Ветки на `origin` |
|---|---|---|---|
| `shop-backend` | `projects/shop-backend` | Laravel 12, PHP 8.4, PostgreSQL | `master`, `release-spring` |
| `shop-frontend` | `projects/shop-frontend` | Nuxt 4, @nuxt/ui, Pinia, orval | `master` |

## shop-backend

- `app/Modules/Catalog/` — единственный модуль: `Models/Product.php`, `Services/ProductService.php`.
- Каталогов `app/Application/` и `app/Infrastructure/` нет: канон слоёв (charter, роли
  `architect` и `backend`) их предусматривает, заводятся первой задачей, которой они нужны.
- `database/migrations/` — одна миграция, `2025_03_01_000000_create_products_table.php`
  (таблица `products` в схеме `public`).
- `tests/Feature/` — PHPUnit; `phpunit.xml` — `pgsql`, база `shop_test`.
- `Makefile` — цели `check` (Pint `--test` + `php artisan test`), `phpstan`, `lint`.
- `phpstan.neon` — уровень 6, `app` и `tests`; CI анализирует только `app`.
- `CLAUDE.md` — устарел (Laravel 10, MySQL), исключён `claudeMdExcludes`.

## shop-frontend

- `app/pages/index.vue` — страница каталога.
- `app/api/` — клиент API, генерирует orval (`orval.config.ts`, вход `openapi.json`):
  `endpoints.ts`, `model/`. Руками не правится.
- `nuxt.config.ts` — модули `@nuxt/ui`, `@pinia/nuxt`, `@nuxt/eslint`; `typescript.typeCheck: true`.
- Скрипты `package.json`: `dev`, `build`, `postinstall` (`nuxt prepare`), `lint`, `lintfix`,
  `generate:api`.

## Точки входа

- API: маршрутов в репозитории пока нет (`routes/` отсутствует).
- Витрина: `app/pages/index.vue`.
