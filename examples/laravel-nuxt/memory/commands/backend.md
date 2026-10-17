---
name: commands-backend
description: Формы вызова для projects/shop-backend — гейты, линт, миграции, грабли инструментов
metadata:
  type: project
---

# Команды — shop-backend

Записано по `Makefile`, `composer.json`, `phpunit.xml` и `.gitlab-ci.yml` при `/beerpowers:setup`;
при setup формы не прогонялись.

`make` на Windows — только через `.claude/bin/make-shim`: системный `make` из PATH уходит
в `cmd` и падает на рецептах. На Linux и macOS `make-shim` — прямой проброс в `make`.

## Гейты

| Гейт | Форма | Зелёный |
|---|---|---|
| Pint + PHPUnit | `.claude/bin/make-shim -C projects/shop-backend check` | Pint без нарушений, итоговая строка PHPUnit без failures и errors |
| PHPStan | `.claude/bin/make-shim -C projects/shop-backend phpstan` | `[OK] No errors` (уровень 6, `app` и `tests`) |
| PHPStan по одному файлу | `projects/shop-backend/vendor/bin/phpstan analyse -c projects/shop-backend/phpstan.neon <файл> --memory-limit 2G --no-progress` | ноль ошибок в файле |

`check` статанализ не включает: гейт — две цели, а не одна. Быстрые гейты — `check` и `phpstan`:
их гоняет и `reviewer` на финальном проходе, если готовых результатов нет.

Тесты идут по PostgreSQL, база `shop_test` (`phpunit.xml`, `DB_CONNECTION=pgsql`).

## Линт

`.claude/bin/make-shim -C projects/shop-backend lint FILES="<файлы>"` — Pint с автофиксом,
пути от корня `projects/shop-backend`, только изменённые файлы.

## Миграции

Применение — `php projects/shop-backend/artisan migrate`; повторный прогон той же командой
проверяет идемпотентность. `docker-compose*.yml` в репозитории нет.

`migrate:fresh`, `migrate:reset`, `db:wipe` — запрещены (`memory/project/safety-rules.md`).

