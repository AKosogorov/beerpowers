# Пресет: Laravel → db

> Фрагменты для слотов `templates/roles/database-agent.md`, когда схема проекта ведётся
> миграциями Laravel и Eloquent. Строки про деньги — если в проекте есть каст денег
> (cknow/laravel-money или свой): его класс назови по проекту. Вместе с пресетом СУБД
> (`presets/postgres/database.md`) — оба раздела слота подряд.

## Слот `ROLE_SCOPE`

- **Миграции** — `database/migrations/`, анонимные классы, идемпотентные.
- **Хранение денег** — VARCHAR + каст денег проекта. Никогда `decimal`, никогда `float`.

Модели Eloquent — совместно с `backend`, если правка касается кастов и связей.

## Слот `SCHEMA_CONVENTIONS`

- **Деньги — VARCHAR + каст денег проекта, никогда float и никогда decimal.** Прецедент
  перевода колонки на строку — назови миграцию проекта, если она есть.

## Слот `MIGRATION_TEMPLATE`

```php
// анонимный класс — конвенция Laravel 12
// 1) схема модуля: create schema if not exists
// 2) таблица: Schema::hasTable() / create ... if not exists
// 3) FK на родителя + ON DELETE CASCADE
// 4) индекс на FK и на колонки фильтра/сортировки (create index if not exists)
// 5) down() возвращает состояние обратно; трансформация данных — с проверкой на повтор
```

## Слот `N_PLUS_ONE`

Связанные данные — одним запросом через `with()`/`load()`, не циклом. Батчи — через
`whereIn`, не запрос на элемент.

## Слот `STACK_CHECKLIST`

- [ ] Денежные колонки — VARCHAR под каст денег проекта, не decimal и не float
